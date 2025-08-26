// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.12;

import {console} from "forge-std/Test.sol";

import {Address} from "@openzeppelin-contract@5.3.0/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin-contract@5.3.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contract@5.3.0/contracts/token/ERC20/utils/SafeERC20.sol";

import {PriceLogic} from "./ChainlinkOp.sol";
import {MoeContract} from "../TradingOp/SwapOperation.sol";

contract TradingContract is PriceLogic, MoeContract {
    using SafeERC20 for IERC20;
    using Address for address;

    IERC20 private constant WMNT =
        IERC20(0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8);

    IERC20 private constant USDT =
        IERC20(0x201EBa5CC46D216Ce6DC03F6a759e8E766e956aE);

    address public constant router = 0xEfB43E833058Cd3464497e57428eFb00dB000763; // Merchant Moe router (LoopingHook)
    address public constant pair = 0x7d35BA038df5afDe64a1962683ffeB3e150637fF; // MNT/USDe LB Pair

    address internal constant LBRouter =
        0xEfB43E833058Cd3464497e57428eFb00dB000763; // Merchant Moe LBRouter

    address internal poolSwap = 0x2bd5E1C8F9f2d2fA2cDdF2C4C8DAc1B8D907C3f5;


    // mnt/usd -> 0xD97F20bEbeD74e8144134C4b148fE93417dd0F96

    // usdt/usd -> 0xd86048D5e4fe96157CE03Ae519A9045bEDaa6551

    constructor(address _priceFeedAddress) PriceLogic(_priceFeedAddress) {}



    struct ShortOp {
        bool isOpen;
        uint16 entryTime;
        uint16 exitTime;
        uint256 entryPrice;
        uint256 exitPrice;
        uint256 amountMntSell;
        uint256 amountUSDTtoBuy;
        uint256 stopLoss;
        uint256 takeProfit;
        int256 result; //in MNT
    }

    uint256 private shortOpCounter;

    mapping(uint256 => ShortOp) private shortOps;

    uint256 private mntBalance;
    uint256 private usdBalance;


    function getShortOpCounter() external view returns (uint256) {
        return shortOpCounter;
    }
    
    function getShortOp(uint256 index) external view returns (ShortOp memory) {
        return shortOps[index];
    }

    function getMntBalance() external view returns (uint256) {
        return mntBalance;
    }

    function getUsdBalance() external view returns (uint256) {
        return usdBalance;
    }



    //* -- EXTERNAL FUNCTIONS TO MANAGE THE STRATEGY -- *//


    function executeShortOpen(
        uint256 entryPrice,
        uint256 exitPrice,
        uint256 amountMntSell,
        uint256 minUsdtToBuy,
        uint256 stopLoss,
        uint256 takeProfit
    ) external returns (bool success) {
        success = _shortOpen(
            entryPrice,
            exitPrice,
            amountMntSell,
            minUsdtToBuy,
            stopLoss,
            takeProfit
        );
    }


    function executeShortClose(uint256 indexOp) external returns (bool success) {
        success = _shortClose(indexOp);
    }







    //*------------------------------ SHORT OPERATIONS --------------------


    function _shortOpen(
        uint256 entryPrice,
        uint256 exitPrice,
        uint256 amountMntSell,
        uint256 minUsdtToBuy,
        uint256 stopLoss,
        uint256 takeProfit
    ) internal returns (bool success) {
        //! per fare short, devo venedere MNT, e prendere usd , questi li posso poi depositare per prendere yield

        uint256 actualCount = shortOpCounter;
        shortOpCounter += 1;

        //? devo innanzitutto capire se ho abbastanza MNT da vendere
        require(
            WMNT.balanceOf(address(this)) >= amountMntSell,
            "Strategy3rd: Not enough MNT to sell for short."
        );

        //? faccio ora lo swap da MNT a USDT
        uint256 usdReceiver = _swapExactTokensForTokens(
            LBRouter,
            amountMntSell,
            address(WMNT),
            0x3B3Ac5386837Dc563660FB6a0937DFAa5924333B, // USDT
            20, // bin step
            poolSwap, // pair MNT/USDT
            address(this)
        );

        require(
            usdReceiver >= minUsdtToBuy,
            "Strategy3rd: Slippage too high on short open swap."
        );

        //? ora registro l'operazione
        ShortOp memory newShort = ShortOp({
            isOpen: true,
            entryTime: uint16(block.timestamp),
            exitTime: 0,
            entryPrice: entryPrice,
            exitPrice: exitPrice,
            amountMntSell: amountMntSell,
            amountUSDTtoBuy: usdReceiver,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            result: 0
        });

        shortOps[actualCount] = newShort;

        return true;
    }

    function _shortClose(uint256 indexOp) internal returns (bool success) {
        ShortOp storage closingOP = shortOps[indexOp];
        require(
            closingOP.isOpen,
            "Strategy3rd: Short operation already closed."
        );

        closingOP.isOpen = false;
        closingOP.exitTime = uint16(block.timestamp);

        //? faccio ora lo swap da USDT a MNT
        uint256 mntReceiver = _swapExactTokensForTokens(
            LBRouter,
            closingOP.amountUSDTtoBuy,
            0x3B3Ac5386837Dc563660FB6a0937DFAa5924333B, // USDT
            address(WMNT),
            20, // bin step
            poolSwap, // pair MNT/USDT
            address(this)
        );

        closingOP.exitPrice = uint256(
            getChainlinkDataFeedLatestAnswer() * 1e10
        );

        if (mntReceiver >= closingOP.amountMntSell) {
            closingOP.result = int256(mntReceiver - closingOP.amountMntSell);
        } else {
            closingOP.result = -int256(closingOP.amountMntSell - mntReceiver);
        }

        return true;
    }



    //*---------------------------------------------------------------------


        function _longOP() internal returns (bool success) {
        //! per fare long, devo depositare MNT, prendere in prestito USD e swapparli in MNT
        // Todo : Capire dove depositare MNT per prendere USD a buon mercato, e gestire il debito e capire quanto ho in valore di MNT per il shanity check
    }




    //* TEST FUNCTIONS

    function putUSDBalance(uint256 amount) external {
        USDT.transferFrom(
            msg.sender,
            address(this),
            amount
        );
        usdBalance += amount;
    }

    function putMNTBalance(uint256 amount) external {
        WMNT.transferFrom(
            msg.sender,
            address(this),
            amount
        );
        mntBalance += amount;
    }

    function withdrawMNT(uint256 amount) external {
        require(
            amount <= mntBalance,
            "TradingContract: Not enough MNT balance to withdraw."
        );
        WMNT.transfer(msg.sender, amount);
        mntBalance -= amount;
    }

    function withdrawUSD(uint256 amount) external {
        require(
            amount <= usdBalance,
            "TradingContract: Not enough USD balance to withdraw."
        );
        USDT.transfer(msg.sender, amount);
        usdBalance -= amount;
    }
}
