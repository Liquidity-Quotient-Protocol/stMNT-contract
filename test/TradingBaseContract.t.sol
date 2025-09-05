// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TradingContract} from "../contracts/TradingOp/TradingContract.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

contract TradingComprehensiveTest is Test {
    IWETH constant WMNT = IWETH(0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8);
    IERC20 private constant USDT = IERC20(0x201EBa5CC46D216Ce6DC03F6a759e8E766e956aE);

    TradingContract tradingContract;
    address user = address(1);

    function setUp() internal {
        tradingContract = new TradingContract(0xD97F20bEbeD74e8144134C4b148fE93417dd0F96);
        tradingContract.setLendingPool(0x44949636f778fAD2b139E665aee11a2dc84A2976);
        tradingContract.setBorrowLendingPool(0xadA66a8722B5cdfe3bC504007A5d793e7100ad09);
        
        console.log("=== SETUP COMPLETED ===");
        console.log("TradingContract deployed at:", address(tradingContract));
        console.log("User address:", user);
    }

    function prepareFunds(uint256 mntAmount, uint256 usdAmount) internal {
        // Setup MNT
        vm.deal(user, mntAmount);
        vm.startPrank(user);
        WMNT.deposit{value: mntAmount}();
        WMNT.approve(address(tradingContract), mntAmount);
        tradingContract.putMNTBalance(mntAmount);
        vm.stopPrank();

        // Setup USDT
        vm.startPrank(0xb24692D17baBEFd97eA2B4ca604A481a7cc2c8EA);
        USDT.transfer(user, usdAmount);
        vm.stopPrank();

        vm.startPrank(user);
        USDT.approve(address(tradingContract), usdAmount);
        tradingContract.putUSDBalance(usdAmount);
        vm.stopPrank();

        console.log("=== FUNDS PREPARED ===");
        console.log("Contract MNT balance:", WMNT.balanceOf(address(tradingContract)));
        console.log("Contract USDT balance:", USDT.balanceOf(address(tradingContract)));
    }

    function testCompleteShortFlow() public {
        setUp();
        console.log("\n=== TESTING COMPLETE SHORT FLOW ===");

        prepareFunds(2 ether, 3000 * 1e6);

        // Log initial state
        uint256 initialMNT = WMNT.balanceOf(address(tradingContract));
        uint256 initialUSDT = USDT.balanceOf(address(tradingContract));
        console.log("Initial MNT:", initialMNT);
        console.log("Initial USDT:", initialUSDT);

        // OPEN SHORT
        console.log("\n--- OPENING SHORT POSITION ---");
        tradingContract.executeShortOpen(
            2000 * 1e18,     // entry price
            1800 * 1e18,     // exit price
            0.8 ether,       // amount MNT to sell
            0,               // min USDT
            2200 * 1e18,     // stop loss
            1600 * 1e18      // take profit
        );

        TradingContract.ShortOp memory shortOp = tradingContract.getShortOp(0);
        console.log("Short opened - MNT sold:", shortOp.amountMntSell);
        console.log("Short opened - USDT received:", shortOp.amountUSDTtoBuy);
        console.log("Short opened - Entry price:", shortOp.entryPrice);
        
        // Verify short opened correctly
        assertTrue(shortOp.isOpen, "Short should be open");
        assertGt(shortOp.amountUSDTtoBuy, 0, "Should have received USDT");

        uint256 mntAfterOpen = WMNT.balanceOf(address(tradingContract));
        uint256 usdtAfterOpen = USDT.balanceOf(address(tradingContract));
        console.log("After open - MNT balance:", mntAfterOpen);
        console.log("After open - USDT balance:", usdtAfterOpen);

        // CLOSE SHORT
        console.log("\n--- CLOSING SHORT POSITION ---");
        tradingContract.executeShortClose(0, 1);

        shortOp = tradingContract.getShortOp(0);
        console.log("Short closed - Exit price:", shortOp.exitPrice);
        console.log("Short closed - Result (MNT):", shortOp.result);
        
        uint256 mntAfterClose = WMNT.balanceOf(address(tradingContract));
        uint256 usdtAfterClose = USDT.balanceOf(address(tradingContract));
        console.log("After close - MNT balance:", mntAfterClose);
        console.log("After close - USDT balance:", usdtAfterClose);

        // Verify short closed correctly
        assertFalse(shortOp.isOpen, "Short should be closed");
     

        console.log("\n=== SHORT FLOW ANALYSIS ===");
        int256 mntDelta = int256(mntAfterClose) - int256(initialMNT);
        int256 usdtDelta = int256(usdtAfterClose) - int256(initialUSDT);
        console.log("Net MNT change:", mntDelta);
        console.log("Net USDT change:", usdtDelta);
        console.log("Result matches calculation:", shortOp.result == mntDelta);
    }

    function testCompleteLongFlow() public {
        setUp();
        console.log("\n=== TESTING COMPLETE LONG FLOW ===");

        prepareFunds(15000 ether, 500 * 1e6);

        // Add extra USDT for closure (come nel tuo test)
        vm.startPrank(0xb24692D17baBEFd97eA2B4ca604A481a7cc2c8EA);
        USDT.transfer(address(tradingContract), 15000 * 1e6);
        vm.stopPrank();

        // Log initial state
        uint256 initialMNT = WMNT.balanceOf(address(tradingContract));
        uint256 initialUSDT = USDT.balanceOf(address(tradingContract));
        console.log("Initial MNT:", initialMNT);
        console.log("Initial USDT:", initialUSDT);

        // OPEN LONG
        console.log("\n--- OPENING LONG POSITION ---");
        tradingContract.openLongOp(
            12000 ether,     // collateral amount
            200 * 1e6,       // borrow amount USDT
            0,               // stop loss
            0,               // take profit
            0,               // min MNT to buy
            0,               // entry price
            0               // exit price
        );

        uint256 longOpCount = tradingContract.getLongOpCounter();
        console.log("Long operations count:", longOpCount);
        assertTrue(longOpCount > 0, "Should have created a long operation");

        uint256 mntAfterOpen = WMNT.balanceOf(address(tradingContract));
        uint256 usdtAfterOpen = USDT.balanceOf(address(tradingContract));
        console.log("After open - MNT balance:", mntAfterOpen);
        console.log("After open - USDT balance:", usdtAfterOpen);

        // Verify long opened correctly
        assertLt(mntAfterOpen, initialMNT, "Should have used MNT as collateral");

        // CLOSE LONG
        console.log("\n--- CLOSING LONG POSITION ---");
        tradingContract.closeLongOp(longOpCount - 1, block.timestamp + 1000);

        uint256 mntAfterClose = WMNT.balanceOf(address(tradingContract));
        uint256 usdtAfterClose = USDT.balanceOf(address(tradingContract));
        console.log("After close - MNT balance:", mntAfterClose);
        console.log("After close - USDT balance:", usdtAfterClose);

        console.log("\n=== LONG FLOW ANALYSIS ===");
        int256 mntDelta = int256(mntAfterClose) - int256(initialMNT);
        int256 usdtDelta = int256(usdtAfterClose) - int256(initialUSDT);
        console.log("Net MNT change:", mntDelta);
        console.log("Net USDT change:", usdtDelta);

        // Basic sanity checks
        assertTrue(mntAfterClose > 0, "Should have some MNT remaining");
        assertTrue(usdtAfterClose > 0, "Should have some USDT remaining");
    }

    function testProfitLossCalculations() public {
        setUp();
        console.log("\n=== TESTING PROFIT/LOSS CALCULATIONS ===");

        prepareFunds(3 ether, 4000 * 1e6);

        // Test multiple short operations with different amounts
        console.log("\n--- Testing Small Short (0.1 MNT) ---");
        tradingContract.executeShortOpen(2000 * 1e18, 1900 * 1e18, 0.1 ether, 0, 0, 0);
        tradingContract.executeShortClose(0, 1);
        
        TradingContract.ShortOp memory smallShort = tradingContract.getShortOp(0);
        console.log("Small short result:", smallShort.result);

        console.log("\n--- Testing Medium Short (0.5 MNT) ---");
        tradingContract.executeShortOpen(2000 * 1e18, 1900 * 1e18, 0.5 ether, 0,  0, 0);
        tradingContract.executeShortClose(1, 1);
        
        TradingContract.ShortOp memory mediumShort = tradingContract.getShortOp(1);
        console.log("Medium short result:", mediumShort.result);

        console.log("\n--- Testing Large Short (1.0 MNT) ---");
        tradingContract.executeShortOpen(2000 * 1e18, 1900 * 1e18, 1.0 ether, 0,  0, 0);
        tradingContract.executeShortClose(2, 1);
        
        TradingContract.ShortOp memory largeShort = tradingContract.getShortOp(2);
        console.log("Large short result:", largeShort.result);

        console.log("\n=== P&L ANALYSIS ===");
        console.log("All operations should show similar loss patterns due to slippage/fees");
        console.log("Larger operations should have proportionally larger absolute losses");
        
        // Basic sanity check - all should be losses due to slippage/fees
        assertTrue(smallShort.result <= 0, "Small short should be loss due to fees");
        assertTrue(mediumShort.result <= 0, "Medium short should be loss due to fees");
        assertTrue(largeShort.result <= 0, "Large short should be loss due to fees");
    }

    function testOperationStates() public {
        setUp();
        console.log("\n=== TESTING OPERATION STATES ===");

        prepareFunds(2 ether, 2000 * 1e6);

        // Test initial state
        uint256 initialShorts = tradingContract.getShortOpCounter();
        console.log("Initial short operations count:", initialShorts);

        // Open operation
        tradingContract.executeShortOpen(2000 * 1e18, 1800 * 1e18, 0.3 ether, 0,  0, 0);
        
        uint256 afterOpenShorts = tradingContract.getShortOpCounter();
        console.log("After open short operations count:", afterOpenShorts);
        assertEq(afterOpenShorts, initialShorts + 1, "Should increment counter");

        TradingContract.ShortOp memory op = tradingContract.getShortOp(initialShorts);
        console.log("Operation state - isOpen:", op.isOpen);
        console.log("Operation state - entryTime:", op.entryTime);
        console.log("Operation state - exitTime:", op.exitTime);
        
        assertTrue(op.isOpen, "Operation should be open");
        assertGt(op.entryTime, 0, "Entry time should be set");
        assertEq(op.exitTime, 0, "Exit time should be zero");

        // Close operation
        tradingContract.executeShortClose(initialShorts, 1);
        
        op = tradingContract.getShortOp(initialShorts);
        console.log("After close - isOpen:", op.isOpen);
        console.log("After close - exitTime:", op.exitTime);
        
        assertFalse(op.isOpen, "Operation should be closed");
        assertGt(op.exitTime, 0, "Exit time should be set");
        assertGe(op.exitTime, op.entryTime, "Exit time should be >= entry time");

        // Verify can't close again
        vm.expectRevert("Strategy3rd: Short operation already closed.");
        tradingContract.executeShortClose(initialShorts, 1);
        
        console.log("State management working correctly");
    }

    function testContractBalances() public {
        setUp();
        console.log("\n=== TESTING CONTRACT BALANCE TRACKING ===");

        prepareFunds(5 ether, 5000 * 1e6);

        uint256 contractMNTBefore = WMNT.balanceOf(address(tradingContract));
        uint256 contractUSDTBefore = USDT.balanceOf(address(tradingContract));
        
        console.log("=== BEFORE OPERATIONS ===");
        console.log("Contract MNT balance:", contractMNTBefore);
        console.log("Contract USDT balance:", contractUSDTBefore);
        console.log("Internal MNT tracking:", tradingContract.getMntBalance());
        console.log("Internal USDT tracking:", tradingContract.getUsdBalance());

        // Perform operation
        tradingContract.executeShortOpen(2000 * 1e18, 1800 * 1e18, 1.5 ether, 0,  0, 0);

        uint256 contractMNTAfter = WMNT.balanceOf(address(tradingContract));
        uint256 contractUSDTAfter = USDT.balanceOf(address(tradingContract));
        
        console.log("\n=== AFTER SHORT OPEN ===");
        console.log("Contract MNT balance:", contractMNTAfter);
        console.log("Contract USDT balance:", contractUSDTAfter);
        console.log("Internal MNT tracking:", tradingContract.getMntBalance());
        console.log("Internal USDT tracking:", tradingContract.getUsdBalance());

        // Close operation
        tradingContract.executeShortClose(0, 1);

        uint256 contractMNTFinal = WMNT.balanceOf(address(tradingContract));
        uint256 contractUSDTFinal = USDT.balanceOf(address(tradingContract));
        
        console.log("\n=== AFTER SHORT CLOSE ===");
        console.log("Contract MNT balance:", contractMNTFinal);
        console.log("Contract USDT balance:", contractUSDTFinal);
        console.log("Internal MNT tracking:", tradingContract.getMntBalance());
        console.log("Internal USDT tracking:", tradingContract.getUsdBalance());

        console.log("\n=== BALANCE CHANGES ===");
        console.log("MNT change:", int256(contractMNTFinal) - int256(contractMNTBefore));
        console.log("USDT change:", int256(contractUSDTFinal) - int256(contractUSDTBefore));

        // Note: Internal tracking might not match actual balances due to trading operations
        // This is expected behavior as the tracking is for user deposits/withdrawals
        console.log("Balance tracking analysis complete");
    }
}