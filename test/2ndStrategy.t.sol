// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StMNT} from "../contracts/Vault.sol";
import {Strategy2nd} from "../contracts/Strategy2nd.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILendingPool, IProtocolDataProvider} from "../contracts/interface/ILendl.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

contract Strg2WithInterestLogging is Test { 
    StMNT public vault;
    Strategy2nd public strategy2nd;

    address public governance = address(1);
    address public management = address(2);
    address public treasury = address(3);
    address public guardian = address(4);
    address public user1 = address(5);



    IWETH public constant WMNT =
        IWETH(address(0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8));

    // LENDING_POOL_ADDRESS per Strategy2nd (Lendle)
    address internal constant LENDLE_LENDING_POOL = 0xCFa5aE7c2CE8Fadc6426C1ff872cA45378Fb7cF3;


    function setUp() public {
        vault = new StMNT(
            address(WMNT),
            governance,
            treasury,
            "stMNT_Test", 
            "stMNT_Test",
            guardian,
            management
        );
        vm.startPrank(governance);
        strategy2nd = new Strategy2nd(address(vault), governance); 
   

        strategy2nd.updateUnlimitedSpending(true); 
        vault.addStrategy(
            address(strategy2nd),
            10_000, // 100% debtRatio
            0,      // minDebtPerHarvest
            type(uint256).max, // maxDebtPerHarvest
            0       // performanceFee
        );
        vault.setPerformanceFee(0);
        vault.setManagementFee(0);
        vault.setDepositLimit(type(uint256).max);
        vm.stopPrank();


        vm.deal(user1, 5000 ether);
    }

    function wrapMNT(uint256 _amount) internal {
        WMNT.deposit{value: _amount}();
    }

    function logSystemState(string memory stageLabel) internal {
        console.log("--- System State: [%s] ---", stageLabel);
        console.log("Block Number: %s, Timestamp: %s", block.number, block.timestamp);
        console.log("Vault TotalSupply: %s", vault.totalSupply());
        console.log("Vault TotalAssets: %s", vault.totalAssets());
        console.log("Vault PricePerShare: %s", vault.pricePerShare());
        console.log("Vault WMNT Balance (totalIdle): %s", WMNT.balanceOf(address(vault)));
        console.log("Vault totalDebt (to strategies): %s", vault.totalDebt());

        (,,,,,,uint256 stratDebtInVault,,) = vault.strategies(address(strategy2nd));
        console.log("Strategy2nd - Debt recorded in Vault: %s", stratDebtInVault);
        console.log("Strategy2nd - Liquid WMNT Balance: %s", WMNT.balanceOf(address(strategy2nd)));
        
        uint256 actualLTokens = IERC20(strategy2nd.lTokenWMNT()).balanceOf(address(strategy2nd));
        console.log("Strategy2nd - Actual lTokenWMNT Balance (on-chain): %s", actualLTokens);
      
        console.log("Strategy2nd - Estimated Total Assets (strategy func): %s", strategy2nd.estimatedTotalAssets());
        console.log("------------------------------------");
    }


    function testDepositAndWithdraw_WithStrategy_WithInterest_DetailedLogs() public returns (uint256) { // Nome test modificato
        console.log("====== Starting Detailed Interest Test for Strategy2nd ======");
        uint256 depositAmount = 1000 ether;

        // --- FASE 0: Stato Iniziale ---
        logSystemState("Initial State");

        // --- FASE 1: DEPOSITO UTENTE ---
        console.log("--- Phase 1: User1 Deposit ---");
        vm.startPrank(user1);
        wrapMNT(depositAmount);
        WMNT.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user1);
        console.log("User1 deposited %s WMNT, received %s shares", depositAmount, shares);
        vm.stopPrank();
        logSystemState("After User1 Deposit, Before 1st Harvest");

        // --- FASE 2: PRIMO HARVEST (Allocazione Fondi alla Strategia) ---
        console.log("--- Phase 2: First Harvest (Funds Allocation) ---");
        vm.startPrank(management);
        strategy2nd.harvest();
        vm.stopPrank();
        logSystemState("After 1st Harvest");
        assertEq(WMNT.balanceOf(address(strategy2nd)), 0, "Strategy liquid want should be 0 after investment");
        assertTrue(IERC20(strategy2nd.lTokenWMNT()).balanceOf(address(strategy2nd)) > 0, "Strategy should have lTokens after investment");

        // --- FASE 3: PRIMO PERIODO DI INTERESSI (60 giorni) ---
        console.log("--- Phase 3: First 60-Day Interest Period ---");
        uint256 pps_before_interest_period1 = vault.pricePerShare();
        skip(60 days);
        logSystemState("After 60 days skip, Before 2nd Harvest");

        // --- FASE 4: SECONDO HARVEST (Report Primo Profitto) ---
        console.log("--- Phase 4: Second Harvest (Report 1st Profit) ---");
        vm.startPrank(management);
        strategy2nd.harvest();
        vm.stopPrank();
        logSystemState("After 2nd Harvest (Profit Reported to Vault, should be Locked)");
        
        uint256 pps_after_profit_report1 = vault.pricePerShare();
        console.log("PPS immediately after 2nd harvest (profit locked): %s", pps_after_profit_report1);
        assertApproxEqAbs(pps_after_profit_report1, pps_before_interest_period1, 2, "PPS should not change much before profit unlock");


        // --- FASE 5: SBLOCCO PRIMO PROFITTO (10 ore) ---
        console.log("--- Phase 5: Unlocking 1st Profit ---");
        skip(10 hours);
        logSystemState("After 10hr skip (1st Profit Unlocked)");
        uint256 pps_after_profit_unlock1 = vault.pricePerShare();
        console.log("PPS after 1st profit unlock: %s", pps_after_profit_unlock1);
        assertTrue(pps_after_profit_unlock1 > pps_before_interest_period1, "PPS should increase after 1st profit unlock");

        // --- FASE 6: SECONDO PERIODO DI INTERESSI (altri 60 giorni) ---
        console.log("--- Phase 6: Second 60-Day Interest Period ---");
        skip(60 days);
        logSystemState("After another 60 days skip, Before 3rd Harvest");

        // --- FASE 7: TERZO HARVEST (Report Secondo Profitto) ---
        console.log("--- Phase 7: Third Harvest (Report 2nd Profit) ---");
        vm.startPrank(management);
        strategy2nd.harvest();
        vm.stopPrank();
        logSystemState("After 3rd Harvest (2nd Profit Reported to Vault, should be Locked)");

        uint256 pps_after_profit_report2 = vault.pricePerShare();
         // Simile a prima, il PPS potrebbe non cambiare molto immediatamente
        assertApproxEqAbs(pps_after_profit_report2, pps_after_profit_unlock1, 2, "PPS should not change much before 2nd profit unlock");

        // --- FASE 8: SBLOCCO SECONDO PROFITTO (10 ore) ---
        console.log("--- Phase 8: Unlocking 2nd Profit ---");
        skip(10 hours);
        logSystemState("After 10hr skip (2nd Profit Unlocked)");
        uint256 pps_final_for_withdraw = vault.pricePerShare();
        console.log("PPS for user withdrawal (after all interest & unlocks): %s", pps_final_for_withdraw);
        assertTrue(pps_final_for_withdraw > pps_after_profit_unlock1, "PPS should increase further after 2nd profit unlock");

        // --- FASE 9: PRELIEVO UTENTE ---
        console.log("--- Phase 9: User1 Withdrawal ---");
        vm.startPrank(user1);
        uint256 initialUserShares = shares; // shares dal deposito iniziale di user1
        uint256 assetsWithdrawn = vault.withdraw(initialUserShares, user1, 100); // maxLoss 0.01%
        console.log("User1 withdrew %s shares for %s WMNT", initialUserShares, assetsWithdrawn);
        vm.stopPrank();
        logSystemState("After User1 Withdrawal");

        console.log("Initial Deposit: %s", depositAmount);
        console.log("Assets Withdrawn: %s", assetsWithdrawn);
        assertGe(assetsWithdrawn, depositAmount, "Withdrawal amount should be >= deposit (interest accrued)");
        // Per un test più stringente, verifica che sia STRETTAMENTE maggiore se ti aspetti profitto netto
        assertTrue(assetsWithdrawn > depositAmount, "Withdrawn assets should be strictly greater due to interest");

        console.log("====== Detailed Interest Test for Strategy2nd COMPLETED ======");
        return assetsWithdrawn; // Modificato per restituire l'importo corretto
    }

    
    function testFullFlow_InterestAccrualAndWithdrawal() public {
        //testInitialize();
        // testDepositAndWithdraw_NoStrategy(); 
        // testDepositAndWithdraw_WithStrategy_NoInterest(); 

        uint256 assets = testDepositAndWithdraw_WithStrategy_WithInterest_DetailedLogs();
    }
}