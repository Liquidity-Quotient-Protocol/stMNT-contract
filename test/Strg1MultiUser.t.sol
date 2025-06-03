// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StMNT} from "../contracts/Vault.sol";
import {Strategy1st} from "../contracts/Strategy1st.sol";
import {IInitCore, ILendingPool} from "../contracts/interface/IInitCore.sol"; // Assicurati che questo percorso sia corretto
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

contract Strg1MultiUser is Test { // Rinominato il contratto di test per chiarezza
    StMNT public vault;
    Strategy1st public strategy1st;

    address public governance = address(1);
    address public management = address(2);
    address public treasury = address(3);
    address public guardian = address(4);
    
    address public userA = address(0xA); // Utente A
    address public userB = address(0xB); // Utente B
    address public userC = address(0xC); // Utente C

    IWETH public constant WMNT =
        IWETH(address(0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8));
    
    address internal constant LENDING_POOL_ADDRESS = 0x44949636f778fAD2b139E665aee11a2dc84A2976;

    function setUp() public {
        vault = new StMNT(
            address(WMNT),
            governance,
            treasury,
            "stMNT_Multi", // Nome leggermente diverso per evitare conflitti se esegui più test
            "stMNT_Multi",
            guardian,
            management
        );
        
        strategy1st = new Strategy1st(address(vault), governance);
        vm.startPrank(governance);
        strategy1st.setLendingPool(LENDING_POOL_ADDRESS);
        strategy1st.updateUnlimitedSpending(true); 
        strategy1st.updateUnlimitedSpendingInit(true);
        strategy1st.approveLendingPool(); 
        
        vault.addStrategy(
            address(strategy1st),
            10_000, 
            0,      
            type(uint256).max, 
            0       
        );
        vault.setPerformanceFee(0); 
        vault.setManagementFee(0);  
        vault.setDepositLimit(type(uint256).max); 
        vm.stopPrank();

        // Fornisci fondi iniziali agli utenti
        vm.deal(userA, 5000 ether);
        vm.deal(userB, 5000 ether);
        vm.deal(userC, 5000 ether);
    }

    function wrapAndApprove(address user, uint256 amount) internal {
        vm.startPrank(user);
        WMNT.deposit{value: amount}();
        WMNT.approve(address(vault), amount);
        vm.stopPrank();
    }

    function depositToVault(address user, uint256 amount) internal returns (uint256 shares) {
        vm.startPrank(user);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
        console.log("User %a deposited %u WMNT, received %u shares.", user, amount, shares);
        console.log("PPS : u%", vault.pricePerShare());
    
    }

    function withdrawFromVault(address user, uint256 shares) internal returns (uint256 assets) {
        vm.startPrank(user);
        assets = vault.withdraw(shares, user, 100); // maxLoss 0.01%
        vm.stopPrank();
        console.log("User %a withdrew %u shares, received %u WMNT. PPS: %u", user, shares, assets);
        console.log("PPS : u%", vault.pricePerShare());
    }

    function executeHarvest() internal {
        vm.startPrank(management);
        strategy1st.harvest();
        vm.stopPrank();
        console.log("Harvest executed. Current PPS: %u", vault.pricePerShare());
    }

    function accrueAndLogLendingPool() internal {
        uint strategySharesInLP = ILendingPool(LENDING_POOL_ADDRESS).balanceOf(address(strategy1st));
        if (strategySharesInLP > 0) {
            uint valueBeforeAccrue = ILendingPool(LENDING_POOL_ADDRESS).toAmt(strategySharesInLP);
            console.log("LendingPool - Value of LP shares BEFORE accrue (toAmt): %u", valueBeforeAccrue);
        }
        
        ILendingPool(LENDING_POOL_ADDRESS).accrueInterest();
        console.log("Called accrueInterest() on LendingPool.");

        if (strategySharesInLP > 0) {
            uint valueAfterAccrue = ILendingPool(LENDING_POOL_ADDRESS).toAmt(strategySharesInLP);
            console.log("LendingPool - Value of LP shares AFTER accrue (toAmt): %u", valueAfterAccrue);
            // Potresti aggiungere un assertTrue qui se ti aspetti sempre un aumento
        }
    }


    function testMultiUser_MixedOperations_InterestAccrual() public {
        console.log("--- Starting Multi-User Test ---");

        uint256 depositA1 = 1000 ether;
        uint256 depositB1 = 1500 ether;

        wrapAndApprove(userA, depositA1);
        uint256 sharesA1 = depositToVault(userA, depositA1);
        
        wrapAndApprove(userB, depositB1);
        uint256 sharesB1 = depositToVault(userB, depositB1);

        executeHarvest(); 
        uint256 pps_after_harvest1 = vault.pricePerShare();

      
        console.log("--- Phase 2: Interest Period & New Deposit ---");
        skip(30 days); 
        accrueAndLogLendingPool();
        executeHarvest();
        
        uint256 pps_after_profit_report = vault.pricePerShare();
        console.log("PPS immediately after profit report (profit locked): %u", pps_after_profit_report);

        skip(8 hours); 
        uint256 pps_after_profit_unlock = vault.pricePerShare();
        console.log("PPS after profit unlock time: %u", pps_after_profit_unlock);
        assertTrue(pps_after_profit_unlock > pps_after_harvest1, "PPS should increase after profit unlock");

        uint256 depositC1 = 800 ether;
        wrapAndApprove(userC, depositC1);
        uint256 sharesC1 = depositToVault(userC, depositC1); // UserC deposita con il nuovo PPS

        console.log("--- Phase 3: Withdrawals & Another Interest Period ---");
        uint256 assetsA_p_prelievo = withdrawFromVault(userA, sharesA1 / 2); // UserA preleva metà
        assertTrue(assetsA_p_prelievo > depositA1 / 2, "UserA partial withdrawal should reflect some profit");

        skip(30 days);
        accrueAndLogLendingPool();
        executeHarvest(); 
        
        pps_after_profit_report = vault.pricePerShare();
        skip(8 hours); 
        pps_after_profit_unlock = vault.pricePerShare();
        console.log("PPS after 2nd profit unlock time: %u", pps_after_profit_unlock);

        console.log("--- Phase 4: Final Withdrawals ---");
        uint256 assetsA_finale = withdrawFromVault(userA, vault.balanceOf(userA)); // UserA preleva il resto
        uint256 assetsB_finale = withdrawFromVault(userB, sharesB1);
        uint256 assetsC_finale = withdrawFromVault(userC, sharesC1);

        uint256 totalWithdrawnA = assetsA_p_prelievo + assetsA_finale;
        
        console.log("UserA: Deposited %u, Withdrew Total %u", depositA1, totalWithdrawnA);
        console.log("UserB: Deposited %u, Withdrew Total %u", depositB1, assetsB_finale);
        console.log("UserC: Deposited %u, Withdrew Total %u", depositC1, assetsC_finale);

        assertTrue(totalWithdrawnA > depositA1, "UserA total withdrawal should be > initial deposit");
        assertTrue(assetsB_finale > depositB1, "UserB total withdrawal should be > initial deposit");
        assertTrue(assetsC_finale > depositC1, "UserC total withdrawal should be > initial deposit (potrebbe essere meno se ha depositato tardi)");

        assertTrue(totalWithdrawnA + assetsB_finale > depositA1 + depositB1, "Combined profit for UserA & B not realized");

        console.log("SUCCESS: Multi-user test with mixed operations and interest completed.");
    }

}