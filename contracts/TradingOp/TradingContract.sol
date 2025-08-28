// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.12;

import {console} from "forge-std/Test.sol";

import {Address} from "@openzeppelin-contract@5.3.0/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin-contract@5.3.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contract@5.3.0/contracts/token/ERC20/utils/SafeERC20.sol";

import {PriceLogic} from "./ChainlinkOp.sol";
import {MoeContract} from "../TradingOp/SwapOperation.sol";
import {Iinit} from "../DefiProtocol/InitProt.sol";

contract TradingContract is PriceLogic, MoeContract, Iinit {
    using SafeERC20 for IERC20;
    using Address for address;

    IERC20 private constant WMNT =
        IERC20(0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8);

    IERC20 private constant USDT =
        IERC20(0x201EBa5CC46D216Ce6DC03F6a759e8E766e956aE);

    address public constant poolSwap =
        0x45A62B090DF48243F12A21897e7ed91863E2c86b; // MNT/USDt

    address internal constant LBRouter =
        0xeaEE7EE68874218c3558b40063c42B82D3E7232a; // Merchant Moe LBRouter

     address public constant _initAddr =
        0x972BcB0284cca0152527c4f70f8F689852bCAFc5;

    address public lendingPool;

    uint256 private balanceShare;

    constructor(address _priceFeedAddress) PriceLogic(_priceFeedAddress) Iinit(_initAddr) {}

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


    function setLendingPool(address _lendingPool) external  {
        require(
            _lendingPool != address(0),
            "Strategy1st: Invalid LendingPool address."
        );
        lendingPool = _lendingPool;
    }

    //* -- EXTERNAL FUNCTIONS TO MANAGE THE STRATEGY -- *//

    function executeShortOpen(
        uint256 entryPrice,
        uint256 exitPrice,
        uint256 amountMntSell,
        uint256 minUsdtToBuy,
        uint256 deadline,
        uint256 stopLoss,
        uint256 takeProfit
    ) external returns (bool success) {
        success = _shortOpen(
            entryPrice,
            exitPrice,
            amountMntSell,
            minUsdtToBuy,
            deadline,
            stopLoss,
            takeProfit
        );
    }

    function executeShortClose(
        uint256 indexOp,uint256 deadline
    ) external returns (bool success) {
        success = _shortClose(indexOp,  deadline);
    }

    //*------------------------------ SHORT OPERATIONS --------------------

    function _shortOpen(
        uint256 entryPrice,
        uint256 exitPrice,
        uint256 amountMntSell,
        uint256 minUsdtToBuy,
        uint256 deadline,
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

        address[] memory path = new address[](2);
        path[0] = address(WMNT);
        path[1] = address(USDT);

        //? faccio ora lo swap da MNT a USDT
        uint256 usdReceiver = _swapExactTokensForTokens(
            LBRouter,
            amountMntSell,
            address(WMNT),
            minUsdtToBuy,
            path,
            address(this),
            deadline
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

    function _shortClose(uint256 indexOp,uint256 deadline) internal returns (bool success) {
        ShortOp storage closingOP = shortOps[indexOp];
        require(
            closingOP.isOpen,
            "Strategy3rd: Short operation already closed."
        );

        closingOP.isOpen = false;
        closingOP.exitTime = uint16(block.timestamp);

        address[] memory path = new address[](2);
        path[0] = address(USDT);
        path[1] = address(WMNT);

        //? faccio ora lo swap da USDT a MNT
        uint256 mntReceiver = _swapExactTokensForTokens(
            LBRouter,
            closingOP.amountUSDTtoBuy,
            address(USDT),
            1, //!! PER ORA VA BENE COSI MA DECO CALCOLARE LO SLIPAGE SE NO ADDIO
            path,
            address(this),
            deadline
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





    //*------------------------------ LONG OPERATIONS --------------------


    uint256 private balanceshare;

    function _depositMNTforUSD(uint256 _amount) internal returns (bool success,uint256 share) {

        uint256 share = depositInit(lendingPool, address(WMNT), _amount, address(this));

        balanceshare += share;

        //! PER ORA CI TENIAMO SEMPLICI MA VANNO AGGIUNTI CONTROLLI E TRACKING DEI DEPOSITI E DEBITI
       success = true;

    }

    bool private positonOpened;
    uint256 private positionId;

    function _createInitPosition() internal returns (bool success,uint256 posId) {
        uint16 mode = 2; // 1 = isolated, 2 = cross
        posId =  createInitPosition(mode, address(this));
        positionId = posId;
        positonOpened = true;
        success = true;
    }




    struct LongOp {
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


    uint256 private longOpCounter;

    mapping(uint256 => ShortOp) private longOps;


    function _longOP(uint256 _amount) internal returns (bool success) {
        //! per fare long, devo depositare MNT, prendere in prestito USD e swapparli in MNT

        (,uint256 share)=_depositMNTforUSD(_amount);

        if(!positonOpened){
            (,uint256 _posId) = _createInitPosition();
            addCollateral(_posId, lendingPool, share);
        }else{
            addCollateral(positionId, lendingPool, share);
        }


    }

    //* TEST FUNCTIONS

    function putUSDBalance(uint256 amount) external {
        USDT.transferFrom(msg.sender, address(this), amount);
        usdBalance += amount;
    }

    function putMNTBalance(uint256 amount) external {
        WMNT.transferFrom(msg.sender, address(this), amount);
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
