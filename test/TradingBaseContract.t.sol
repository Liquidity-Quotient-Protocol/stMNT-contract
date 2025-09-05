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

contract TradingContractTest is Test {
    TradingContract public tradingContract;
    
    IWETH public constant WMNT = IWETH(0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8);
    IERC20 public constant USDT = IERC20(0x201EBa5CC46D216Ce6DC03F6a759e8E766e956aE);
    
    address public admin = address(1);
    address public aiAgent = address(2);
    address public guardian = address(3);
    address public user = address(4);
    
    address public constant USDT_WHALE = 0xb24692D17baBEFd97eA2B4ca604A481a7cc2c8EA;

    function setUp() public {
        vm.startPrank(admin);
        tradingContract = new TradingContract(0xD97F20bEbeD74e8144134C4b148fE93417dd0F96);
        tradingContract.setLendingPool(0x44949636f778fAD2b139E665aee11a2dc84A2976);
        tradingContract.setBorrowLendingPool(0xadA66a8722B5cdfe3bC504007A5d793e7100ad09);
        tradingContract.grantRole(tradingContract.AI_AGENT(), aiAgent);
        tradingContract.grantRole(tradingContract.GUARDIAN_ROLE(), guardian);
        vm.stopPrank();
        
        console.log("Setup completed");
    }

    function prepareFunds(uint256 mntAmount, uint256 usdAmount) internal {
        vm.deal(user, mntAmount);
        vm.startPrank(user);
        WMNT.deposit{value: mntAmount}();
        WMNT.approve(address(tradingContract), mntAmount);
        tradingContract.putMNTBalance(mntAmount);
        vm.stopPrank();
        
        vm.startPrank(USDT_WHALE);
        USDT.transfer(user, usdAmount);
        vm.stopPrank();
        
        vm.startPrank(user);
        USDT.approve(address(tradingContract), usdAmount);
        tradingContract.putUSDBalance(usdAmount);
        vm.stopPrank();
        
        console.log("Funds prepared - MNT:", mntAmount, "USDT:", usdAmount);
    }

    function testSimpleShortFlow() public {
        console.log("\n=== SIMPLE SHORT TEST ===");
        
        prepareFunds(2 ether, 3000 * 1e6);
        
        uint256 initialMNT = WMNT.balanceOf(address(tradingContract));
        console.log("Initial MNT balance:", initialMNT);
        
        // Open short
        vm.startPrank(aiAgent);
        tradingContract.executeShortOpen(
            2000 * 1e18,  // entryPrice
            1800 * 1e18,  // exitPrice
            0.8 ether,    // amountMntSell
            0,            // minUsdtToBuy
            0,            // stopLoss
            0             // takeProfit
        );
        vm.stopPrank();
        
        TradingContract.ShortOp memory shortOp = tradingContract.getShortOp(0);
        console.log("Short opened - MNT sold:", shortOp.amountMntSell);
        console.log("Short opened - USDT received:", shortOp.amountUSDTtoBuy);
        assertTrue(shortOp.isOpen, "Short should be open");
        
        // Add time gap to fix timing issue
        vm.warp(block.timestamp + 1);
        
        // Close short
        vm.startPrank(guardian);
        tradingContract.executeShortClose(0, 0);
        vm.stopPrank();
        
        shortOp = tradingContract.getShortOp(0);
        console.log("Short closed - Result:", shortOp.result);
        assertFalse(shortOp.isOpen, "Short should be closed");
        
        uint256 finalMNT = WMNT.balanceOf(address(tradingContract));
        console.log("Final MNT balance:", finalMNT);
        console.log("MNT change:", int256(finalMNT) - int256(initialMNT));
        
        console.log("Short test completed successfully");
    }

    function testMultipleShorts() public {
        console.log("\n=== MULTIPLE SHORTS TEST ===");
        
        prepareFunds(5 ether, 8000 * 1e6);
        
        vm.startPrank(aiAgent);
        
        // Open 3 short positions
        for(uint i = 0; i < 3; i++) {
            uint256 amount = (i + 1) * 0.3 ether;
            tradingContract.executeShortOpen(2000 * 1e18, 1800 * 1e18, amount, 0, 0, 0);
            console.log("Opened short", i, "with amount:", amount);
        }
        
        vm.stopPrank();
        
        assertEq(tradingContract.getShortOpCounter(), 3, "Should have 3 shorts");
        
        // Close all positions
        vm.startPrank(guardian);
        for(uint i = 0; i < 3; i++) {
            vm.warp(block.timestamp + 1); // Add time gap
            tradingContract.executeShortClose(i, 0);
            
            TradingContract.ShortOp memory shortOp = tradingContract.getShortOp(i);
        }
        vm.stopPrank();
        
        console.log("Multiple shorts test completed");
    }

    function testAccessControl() public {
        console.log("\n=== ACCESS CONTROL TEST ===");
        
        prepareFunds(1 ether, 1000 * 1e6);
        
        // User cannot open short
        vm.startPrank(user);
        vm.expectRevert("Not an AI agent");
        tradingContract.executeShortOpen(2000 * 1e18, 1800 * 1e18, 0.5 ether, 0, 0, 0);
        vm.stopPrank();
        
        // Open position as AI agent
        vm.startPrank(aiAgent);
        tradingContract.executeShortOpen(2000 * 1e18, 1800 * 1e18, 0.5 ether, 0, 0, 0);
        vm.stopPrank();
        
        // User cannot close
        vm.startPrank(user);
        vm.expectRevert("Not authorized");
        tradingContract.executeShortClose(0, 0);
        vm.stopPrank();
        
        // Guardian can close
        vm.warp(block.timestamp + 1);
        vm.startPrank(guardian);
        tradingContract.executeShortClose(0, 0);
        vm.stopPrank();
        
        console.log("Access control test passed");
    }

    function testErrorConditions() public {
        console.log("\n=== ERROR CONDITIONS TEST ===");
        
        prepareFunds(0.1 ether, 100 * 1e6);
        
        vm.startPrank(aiAgent);
        
        // Try to sell more MNT than available - should revert with custom error
        vm.expectRevert(abi.encodeWithSignature("InsufficientMNT()"));
        tradingContract.executeShortOpen(2000 * 1e18, 1800 * 1e18, 10 ether, 0, 0, 0);
        
        // Open a position first
        tradingContract.executeShortOpen(2000 * 1e18, 1800 * 1e18, 0.05 ether, 0, 0, 0);
        
        vm.warp(block.timestamp + 1);
        
        // Close it
        tradingContract.executeShortClose(0, 0);
        
        // Try to close again - should revert with custom error
        vm.expectRevert(abi.encodeWithSignature("PositionAlreadyClosed()"));
        tradingContract.executeShortClose(0, 0);
        
        vm.stopPrank();
        
        console.log("Error conditions test passed");
    }

    function testContractState() public {
        console.log("\n=== CONTRACT STATE TEST ===");
        
        prepareFunds(2 ether, 2000 * 1e6);
        
        console.log("Initial state:");
        console.log("- Short counter:", tradingContract.getShortOpCounter());
        console.log("- Long counter:", tradingContract.getLongOpCounter());
        console.log("- MNT tracking:", tradingContract.getMntBalance());
        console.log("- USDT tracking:", tradingContract.getUsdBalance());
        
        vm.startPrank(aiAgent);
        tradingContract.executeShortOpen(2000 * 1e18, 1800 * 1e18, 0.5 ether, 0, 0, 0);
        vm.stopPrank();
        
        console.log("After opening short:");
        console.log("- Short counter:", tradingContract.getShortOpCounter());
        console.log("- Contract MNT:", WMNT.balanceOf(address(tradingContract)));
        console.log("- Contract USDT:", USDT.balanceOf(address(tradingContract)));
        
        TradingContract.ShortOp memory shortOp = tradingContract.getShortOp(0);
        console.log("- Position open:", shortOp.isOpen);
        console.log("- Entry time:", shortOp.entryTime);
        
        vm.warp(block.timestamp + 1);
        vm.startPrank(guardian);
        tradingContract.executeShortClose(0, 0);
        vm.stopPrank();
        
        shortOp = tradingContract.getShortOp(0);
        console.log("After closing short:");
        console.log("- Position open:", shortOp.isOpen);
        console.log("- Exit time:", shortOp.exitTime);
        console.log("- Result:", shortOp.result);
        
        console.log("Contract state test completed");
    }

    // Main test function
    function testAllBasicFunctionality() public {
        testSimpleShortFlow();
        setUp(); // Reset
        
        testMultipleShorts();
        setUp(); // Reset
        
        testAccessControl();
        setUp(); // Reset
        
        testErrorConditions();
        setUp(); // Reset
        
        testContractState();
        
        console.log("\n=== ALL BASIC TESTS COMPLETED ===");
    }
}