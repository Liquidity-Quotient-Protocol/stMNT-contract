// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StMNT} from "../contracts/Vault.sol";
import {Strategy2nd} from "../contracts/Strategy2nd.sol";
import {IInitCore, ILendingPool} from "../contracts/interface/IInitCore.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

contract Strg2EmergencyTest is
    Test 
{
    StMNT public vault;
    Strategy2nd public strategy2nd;

    address public governance = address(1);
    address public management = address(2);
    address public treasury = address(3);
    address public guardian = address(4);
    address public user1 = address(0xA); 
    address public user2 = address(0xB);
    address public user3 = address(0xC);

    IWETH public constant WMNT =
        IWETH(address(0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8));

    address internal constant LENDING_POOL_ADDRESS =
        0x44949636f778fAD2b139E665aee11a2dc84A2976;

      function setUp() public {
        vault = new StMNT(
            address(WMNT),
            governance,
            treasury,
            "stMNT_Multi2", 
            "stMNT_Multi2",
            guardian,
            management
        );
        
        // Setup per Strategy2nd
        vm.startPrank(governance);
        strategy2nd = new Strategy2nd(address(vault), governance);
        // In Strategy2nd, lendingPool è una costante e lTokenWMNT è determinato nel costruttore.
        // Non c'è setLendingPool da chiamare.
        
        strategy2nd.updateUnlimitedSpending(true); // Strategia approva vault per 'want' (WMNT)
        // L'approve per il lendingPool di Lendle per spendere WMNT dalla strategia
        // è già fatto nel costruttore di Strategy2nd.
        // strategy2nd.updateUnlimitedSpendingLendl(true); // Questo è ridondante.
        
        vault.addStrategy(
            address(strategy2nd),
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
        vm.deal(user1, 5000 ether);
        vm.deal(user2, 5000 ether);
        vm.deal(user3, 5000 ether);
    }
    function wrapAndDeposit(address user, uint256 amount) internal {
        vm.startPrank(user);
        WMNT.deposit{value: amount}();
        WMNT.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, user);
        console.log(
            "User %s deposited %s WMNT, received %s shares.",
            user,
            amount,
            shares
        );

        console.log("Vault TotalSupply: %s",vault.totalSupply());
        console.log("Vault TotalAssets: %s",vault.totalAssets());




        vm.stopPrank();
    }

    function executeHarvest(string memory label) internal {
        console.log("--- Executing Harvest: [%s] ---", label);
        vm.startPrank(management);
        strategy2nd.harvest();
        vm.stopPrank();
        logCurrentState(string.concat("After Harvest [", label, "]"));
    }

    function logCurrentState(string memory stage) internal {
        console.log("--- State Check: [%s] ---", stage);
        console.log(
            "Vault WMNT (totalIdle): %s",
            WMNT.balanceOf(address(vault))
        );
        console.log("Vault totalDebt: %s", vault.totalDebt());
        console.log("Vault totalAssets: %s", vault.totalAssets());
        console.log("Vault PricePerShare: %s", vault.pricePerShare());

(,,,,,, uint256 stratTotalDebt, , ) = vault.strategies(address(strategy2nd));
      
        console.log("Strategy totalDebt in Vault: %s", stratTotalDebt);

        uint256 stratWantBal = WMNT.balanceOf(address(strategy2nd));
        console.log("Strategy WMNT Balance (liquid): %s", stratWantBal);

        uint256 stratLPShares = ILendingPool(LENDING_POOL_ADDRESS).balanceOf(
            address(strategy2nd)
        );
        console.log("Strategy LP Shares in LendingPool: %s", stratLPShares);
        if (stratLPShares > 0) {
            uint256 stratLPValue = ILendingPool(LENDING_POOL_ADDRESS)
                .toAmtCurrent(stratLPShares);
            console.log(
                "Strategy Value of LP Shares (toAmtCurrent): %s",
                stratLPValue
            );
        }
        console.log(
            "Strategy internal balanceShare (getter): %s",
            strategy2nd.getBalanceShare() //! Getter create for testing
        ); 
    }

    function testEmergencyWithdraw_FullCycle() public {

        console.log("--- Starting Emergency Withdraw Test ---");
        uint256 deposit1User1 = 1000 ether;
        wrapAndDeposit(user1, deposit1User1);

        uint256 deposit1User2 = 216 ether;
        wrapAndDeposit(user2, deposit1User2);

        executeHarvest("Initial Allocation"); 

        uint256 expectedTotalDebtAfterAlloc1 = deposit1User1 + deposit1User2;
    
        (,,,,,, uint256 stratDebt1, , ) = vault.strategies(address(strategy2nd));
        assertApproxEqAbs(
            stratDebt1,
            expectedTotalDebtAfterAlloc1,
            1,
            "Strategy debt not correctly allocated after 1st harvest batch"
        );
        assertTrue(
            strategy2nd.getBalanceShare() > 0,
            "Strategy should have LP shares after investment"
        );

        skip(5 days); 
        ILendingPool(LENDING_POOL_ADDRESS).accrueInterest();

        uint256 deposit1User3 = 154 ether;
        wrapAndDeposit(user3, deposit1User3);

        executeHarvest("Second Allocation & Minor Interest");
        uint256 expectedTotalDebtAfterAlloc2 = expectedTotalDebtAfterAlloc1 +
            deposit1User3; 
        (,,,,,, uint256 stratDebt2, , ) = vault.strategies(address(strategy2nd));
        
        console.log(
            "Expected total debt in strategy ~%s, actual: %s",
            expectedTotalDebtAfterAlloc2,
            stratDebt2
        );
        assertTrue(
            strategy2nd.getBalanceShare() > 0,
            "Strategy should still have LP shares"
        );

        uint256 strategyLPValueBeforeEmergency = ILendingPool(
            LENDING_POOL_ADDRESS
        ).toAmtCurrent(strategy2nd.getBalanceShare());
        console.log(
            "Value in LP held by strategy BEFORE emergency: %s",
            strategyLPValueBeforeEmergency
        );
        assertTrue(
            strategyLPValueBeforeEmergency > 0,
            "Strategy should have value in LP before emergency"
        );

        console.log("--- Triggering Emergency Exit ---");
        vm.startPrank(management); 
        strategy2nd.setEmergencyExit();
        vm.stopPrank();

        assertTrue(
            strategy2nd.emergencyExit(),
            "Strategy emergencyExit flag should be true"
        );
  
        (,,uint256 stratDebtRatioAfterRevoke,,,,, , ) = vault.strategies(address(strategy2nd));
        assertEq(
            stratDebtRatioAfterRevoke,
            0,
            "Strategy debtRatio in Vault should be 0 after revoke"
        );

        skip(1 hours);
      
        executeHarvest("Emergency Harvest"); 


        console.log("--- Post-Emergency State Verification ---");
        uint256 finalStrategyWantBalance = WMNT.balanceOf(address(strategy2nd));
        assertApproxEqAbs(
            finalStrategyWantBalance,
            0,
            100,
            "Strategy WMNT balance should be ~0 after emergency harvest"
        );

        uint256 finalStrategyLPShares = strategy2nd.getBalanceShare(); // Controlla la variabile interna
        assertApproxEqAbs(
            finalStrategyLPShares,
            0,
            100,
            "Strategy internal balanceShare should be ~0 after emergency"
        );

        (,,,,,, uint256 finalStratTotalDebtInVault, , ) = vault.strategies(address(strategy2nd));


        assertApproxEqAbs(
            finalStratTotalDebtInVault,
            0,
            100,
            "Strategy totalDebt in Vault should be ~0 after emergency"
        );

        uint256 finalVaultWantBalance = WMNT.balanceOf(address(vault));
        console.log(
            "Vault final WMNT balance (totalIdle): %s",
            finalVaultWantBalance
        );
        uint256 totalDeposits = deposit1User1 + deposit1User2 + deposit1User3;
        assertTrue(
            finalVaultWantBalance >= totalDeposits,
            "Vault balance should be at least total deposits"
        );
        assertApproxEqAbs(
            finalVaultWantBalance,
            strategyLPValueBeforeEmergency,
            strategyLPValueBeforeEmergency / 1000,
            "Vault balance should be close to value held by strategy before emergency"
        );

        skip(10 hours);

        console.log("--- User Withdrawals Post-Emergency ---");
        uint256 ppsAfterEmergency = vault.pricePerShare();
        console.log(
            "PPS for user withdrawals after emergency: %s",
            ppsAfterEmergency
        );

        vm.startPrank(user1);
        uint256 sharesUser1 = vault.balanceOf(user1);
        uint256 withdrawnUser1 = vault.withdraw(sharesUser1, user1, 100); // maxLoss 0.01%
        console.log(
            "User1 (0xA) withdrew %s shares for %s WMNT",
            sharesUser1,
            withdrawnUser1
        );
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 sharesUser2 = vault.balanceOf(user2);
        uint256 withdrawnUser2 = vault.withdraw(sharesUser2, user2, 100);
        console.log(
            "User2 (0xB) withdrew %s shares for %s WMNT",
            sharesUser2,
            withdrawnUser2
        );
        vm.stopPrank();


        vm.startPrank(user3);
        uint256 sharesUser3 = vault.balanceOf(user3);
        uint256 withdrawnUser3 = vault.withdraw(sharesUser3, user3, 100);
        console.log(
            "User3 (0xC) withdrew %s shares for %s WMNT",
            sharesUser3,
            withdrawnUser3
        );
        vm.stopPrank();

        uint256 totalWithdrawnByUsers = withdrawnUser1 +
            withdrawnUser2 +
            withdrawnUser3;
        assertApproxEqAbs(
            totalWithdrawnByUsers,
            finalVaultWantBalance,
            1000,
            "Total withdrawn by users should match funds recovered to vault (allowing for dust)"
        );
        assertApproxEqAbs(
            WMNT.balanceOf(address(vault)),
            0,
            1000,
            "Vault should be near empty after all users withdraw"
        );

        console.log("SUCCESS: Emergency withdraw test completed and verified.");
    }
}
