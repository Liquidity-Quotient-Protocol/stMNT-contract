// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StMNT} from "../contracts/Vault.sol";
import {Strategy2nd} from "../contracts/Strategy2nd.sol";
import {ILendingPool} from "../contracts/interface/ILendl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

contract Strg2EmergencyTest is Test {
    StMNT public vault;
    Strategy2nd public strategy2nd;

    address public governance = address(1);
    address public management = address(2);
    address public treasury = address(3);
    address public guardian = address(4);
    address public userA = address(0xA);
    address public userB = address(0xB);
    address public userC = address(0xC);

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

        vm.startPrank(governance);
        strategy2nd = new Strategy2nd(address(vault), governance);

        strategy2nd.updateUnlimitedSpending(true); 
    

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

      
        vm.deal(userA, 5000 ether);
        vm.deal(userB, 5000 ether);
        vm.deal(userC, 5000 ether);
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

        console.log("Vault TotalSupply: %s", vault.totalSupply());
        console.log("Vault TotalAssets: %s", vault.totalAssets());

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

        (, , , , , , uint256 stratTotalDebt, , ) = vault.strategies(
            address(strategy2nd)
        );

        console.log("Strategy totalDebt in Vault: %s", stratTotalDebt);

        uint256 stratWantBal = WMNT.balanceOf(address(strategy2nd));
        console.log("Strategy WMNT Balance (liquid): %s", stratWantBal);

   
    }

    function testEmergencyWithdraw_FullCycle() public {
        console.log("--- Starting Emergency Withdraw Test ---");
        uint256 deposit1userA = 1000 ether;
        wrapAndDeposit(userA, deposit1userA);

        uint256 deposit1userB = 216 ether;
        wrapAndDeposit(userB, deposit1userB);

        executeHarvest("Initial Allocation");

        uint256 expectedTotalDebtAfterAlloc1 = deposit1userA + deposit1userB;

        (, , , , , , uint256 stratDebt1, , ) = vault.strategies(
            address(strategy2nd)
        );
        assertApproxEqAbs(
            stratDebt1,
            expectedTotalDebtAfterAlloc1,
            1,
            "Strategy debt not correctly allocated after 1st harvest batch"
        );

        skip(5 days);

        uint256 deposit1userC = 154 ether;
        wrapAndDeposit(userC, deposit1userC);

        executeHarvest("Second Allocation & Minor Interest");
        uint256 expectedTotalDebtAfterAlloc2 = expectedTotalDebtAfterAlloc1 +
            deposit1userC;
        (, , , , , , uint256 stratDebt2, , ) = vault.strategies(
            address(strategy2nd)
        );

        console.log(
            "Expected total debt in strategy ~%s, actual: %s",
            expectedTotalDebtAfterAlloc2,
            stratDebt2
        );
    

      

        console.log("--- Triggering Emergency Exit ---");
        vm.startPrank(management);
        strategy2nd.setEmergencyExit();
        vm.stopPrank();

        assertTrue(
            strategy2nd.emergencyExit(),
            "Strategy emergencyExit flag should be true"
        );

        (, , uint256 stratDebtRatioAfterRevoke, , , , , , ) = vault.strategies(
            address(strategy2nd)
        );
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

    

        (, , , , , , uint256 finalStratTotalDebtInVault, , ) = vault.strategies(
            address(strategy2nd)
        );

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
        uint256 totalDeposits = deposit1userA + deposit1userB + deposit1userC;
        assertTrue(
            finalVaultWantBalance >= totalDeposits,
            "Vault balance should be at least total deposits"
        );


        skip(10 hours);

        console.log("--- User Withdrawals Post-Emergency ---");
        uint256 ppsAfterEmergency = vault.pricePerShare();
        console.log(
            "PPS for user withdrawals after emergency: %s",
            ppsAfterEmergency
        );

        vm.startPrank(userA);
        uint256 sharesuserA = vault.balanceOf(userA);
        uint256 withdrawnuserA = vault.withdraw(sharesuserA, userA, 100); // maxLoss 0.01%
        console.log(
            "userA (0xA) withdrew %s shares for %s WMNT",
            sharesuserA,
            withdrawnuserA
        );
        vm.stopPrank();

        vm.startPrank(userB);
        uint256 sharesuserB = vault.balanceOf(userB);
        uint256 withdrawnuserB = vault.withdraw(sharesuserB, userB, 100);
        console.log(
            "userB (0xB) withdrew %s shares for %s WMNT",
            sharesuserB,
            withdrawnuserB
        );
        vm.stopPrank();

        vm.startPrank(userC);
        uint256 sharesuserC = vault.balanceOf(userC);
        uint256 withdrawnuserC = vault.withdraw(sharesuserC, userC, 100);
        console.log(
            "userC (0xC) withdrew %s shares for %s WMNT",
            sharesuserC,
            withdrawnuserC
        );
        vm.stopPrank();

        uint256 totalWithdrawnByUsers = withdrawnuserA +
            withdrawnuserB +
            withdrawnuserC;
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
