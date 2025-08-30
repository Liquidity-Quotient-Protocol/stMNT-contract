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

contract TradingBaseContract is Test {
    IWETH constant WMNT = IWETH(0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8);
    IERC20 private constant USDT =
        IERC20(0x201EBa5CC46D216Ce6DC03F6a759e8E766e956aE);

    TradingContract tradingContract;

    function setUp() internal {
        tradingContract = new TradingContract(
            0xD97F20bEbeD74e8144134C4b148fE93417dd0F96
        );

        tradingContract.setLendingPool(
            0x44949636f778fAD2b139E665aee11a2dc84A2976
        );

        tradingContract.setBorrowLendingPool(
            0xadA66a8722B5cdfe3bC504007A5d793e7100ad09
        );
    }

    function getMeMNT(address _user, uint256 _amount) internal {
        vm.deal(_user, _amount);
        vm.startPrank(_user);
        WMNT.deposit{value: _amount}();
        vm.stopPrank();
    }

    function getMeUSD(address _user, uint256 _amount) internal {
        vm.startPrank(0xb24692D17baBEFd97eA2B4ca604A481a7cc2c8EA); //whale
        USDT.transfer(_user, _amount);
        vm.stopPrank();
    }

    function depoistMNTtoContract(address _user, uint256 _amount) internal {
        vm.startPrank(_user);
        WMNT.approve(address(tradingContract), _amount);
        tradingContract.putMNTBalance(_amount);
        vm.stopPrank();
    }

    function depoistUSDtoContract(address _user, uint256 _amount) internal {
        vm.startPrank(_user);
        USDT.approve(address(tradingContract), _amount);
        tradingContract.putUSDBalance(_amount);
        vm.stopPrank();
    }

    function openShortOp(
        uint256 entryPrice,
        uint256 exitPrice,
        uint256 amountMntSell,
        uint256 minUsdtToBuy,
        uint256 deadline,
        uint256 stopLoss,
        uint256 takeProfit
    ) internal {
        tradingContract.executeShortOpen(
            entryPrice,
            exitPrice,
            amountMntSell,
            minUsdtToBuy,
            stopLoss,
            takeProfit,
            deadline
        );

        TradingContract.ShortOp memory op = tradingContract.getShortOp(
            tradingContract.getShortOpCounter() - 1
        );
        assert(op.isOpen == true);
        //console.log("Short Operation opened successfully");
        //console.log("Entry Price:", op.entryPrice);
        //console.log("Exit Price:", op.exitPrice);
        //console.log("Amount MNT Sold:", op.amountMntSell);
        //console.log("Amount USDT Bought:", op.amountUSDTtoBuy);
        //console.log("Stop Loss:", op.stopLoss);
        //console.log("Take Profit:", op.takeProfit);
    }

    function closeShortOp(uint256 index) internal {
        tradingContract.executeShortClose(index, block.timestamp + 1000);
        TradingContract.ShortOp memory op = tradingContract.getShortOp(index);
        assert(op.isOpen == false);
        //console.log("Short Operation closed successfully");
        //console.log("Entry Price:", op.entryPrice);
        //console.log("Exit Price:", op.exitPrice);
        //console.log("Amount MNT Sold:", op.amountMntSell);
        //console.log("Amount USDT Bought:", op.amountUSDTtoBuy);
        //console.log("Stop Loss:", op.stopLoss);
        //console.log("Take Profit:", op.takeProfit);
        //console.log("Result (in MNT):", op.result);
    }

    function testSetUp() public {
        setUp();
        assert(address(tradingContract) != address(0));
        //console.log("TradingContract deployed at:", address(tradingContract));
    }

    function testSimpleShort() public {
        setUp();

        address user = address(1);
        uint256 mntAmount = 1 ether;
        uint256 usdAmount = 2000 * 1e6;

        getMeMNT(user, mntAmount);
        getMeUSD(user, usdAmount);

        depoistMNTtoContract(user, mntAmount);
        depoistUSDtoContract(user, usdAmount);

        uint256 initialUSDTBalance = USDT.balanceOf(address(tradingContract));
        openShortOp(
            2000 * 1e18,
            1800 * 1e18,
            0.5 ether,
            0,
            block.timestamp + 1000,
            2100 * 1e18,
            1700 * 1e18
        );

        assertGt(USDT.balanceOf(address(tradingContract)), initialUSDTBalance);
        //console.log("More USDt then start");
    }

    function testSimpleShortOpenAndClose() public {
        setUp();

        address user = address(1);
        uint256 mntAmount = 1 ether;
        uint256 usdAmount = 2000 * 1e6;

        getMeMNT(user, mntAmount);
        getMeUSD(user, usdAmount);

        depoistMNTtoContract(user, mntAmount);
        depoistUSDtoContract(user, usdAmount);

        uint256 initialUSDTBalance = USDT.balanceOf(address(tradingContract));
        openShortOp(
            2000 * 1e18,
            1800 * 1e18,
            0.5 ether,
            0,
            block.timestamp + 1000,
            2100 * 1e18,
            1700 * 1e18
        );

        assertGt(
            USDT.balanceOf(address(tradingContract)),
            initialUSDTBalance,
            "TradingContract should have more USDT after opening short."
        );

        closeShortOp(tradingContract.getShortOpCounter() - 1);

        //assertEq(
        //    USDT.balanceOf(address(tradingContract)),
        //    initialUSDTBalance,
        //    "TradingContract should have the same USDT after closing short."
        //);
    }

    function testSimpleLong() public {
        setUp();

        address user = address(1);
        uint256 mntAmount = 10_000 ether;
        uint256 usdAmount = 100 * 1e6;

        getMeMNT(user, mntAmount);
        getMeUSD(user, usdAmount);

        depoistMNTtoContract(user, mntAmount);

        //console.log("Sono arrivato qui!");
        tradingContract.openLongOp(
            9_000 ether,
            usdAmount,
            0,
            0,
            0,
            0,
            0,
            block.timestamp + 1000
        );
    }
}
