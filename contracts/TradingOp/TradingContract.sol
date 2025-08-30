// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.12;

import {console} from "forge-std/Test.sol";

import {Address} from "@openzeppelin-contract@5.3.0/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin-contract@5.3.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contract@5.3.0/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721Receiver} from "@openzeppelin-contract@5.3.0/contracts/token/ERC721/IERC721Receiver.sol";

import {PriceLogic} from "./ChainlinkOp.sol";
import {MoeContract} from "../TradingOp/SwapOperation.sol";
import {Iinit} from "../DefiProtocol/InitProt.sol";

contract TradingContract is PriceLogic, MoeContract, Iinit, IERC721Receiver {
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

    address public borrowLeningPool;

    uint256 private balanceShare;

    constructor(
        address _priceFeedAddress
    ) PriceLogic(_priceFeedAddress) Iinit(_initAddr) {}

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

    function setLendingPool(address _lendingPool) external {
        require(
            _lendingPool != address(0),
            "Strategy1st: Invalid LendingPool address."
        );
        lendingPool = _lendingPool;
    }

    function setBorrowLendingPool(address _lendingPool) external {
        require(
            _lendingPool != address(0),
            "Strategy1st: Invalid LendingPool address."
        );
        borrowLeningPool = _lendingPool;
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
        uint256 indexOp,
        uint256 deadline
    ) external returns (bool success) {
        success = _shortClose(indexOp, deadline);
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

    function _shortClose(
        uint256 indexOp,
        uint256 deadline
    ) internal returns (bool success) {
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

    function _depositMNTforUSD(
        uint256 _amount
    ) internal returns (bool success, uint256 share) {
        share = depositInit(lendingPool, address(WMNT), _amount, address(this));

        balanceshare += share;

        //! PER ORA CI TENIAMO SEMPLICI MA VANNO AGGIUNTI CONTROLLI E TRACKING DEI DEPOSITI E DEBITI
        success = true;
    }

    bool private positonOpened;
    uint256 private positionId;

    function _createInitPosition()
        internal
        returns (bool success, uint256 posId)
    {
        uint16 mode = 1; // 1 = isolated, 2 = cross
        posId = createInitPosition(mode, address(this));
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
    uint256 private debtUSDTShares;

    mapping(uint256 => LongOp) private longOps;

    function _longOP(
        uint256 _amountColl,
        uint256 _amountBorrow,
        uint256 stopLoss,
        uint256 takeProfit,
        uint256 deadline,
        uint256 minMntToBuy,
        uint256 entryPrice,
        uint256 exitPrice
    ) internal returns (bool success) {
        //! per fare long, devo depositare MNT, prendere in prestito USD e swapparli in MNT
        require(
            WMNT.balanceOf(address(this)) >= _amountColl,
            "TradingContract: Not enough MNT to deposit for long."
        );

        uint256 actualCount = longOpCounter;
        longOpCounter += 1;

        (, uint256 share) = _depositMNTforUSD(_amountColl);

        if (!positonOpened) {
            (, uint256 _posId) = _createInitPosition();
            addCollateral(_posId, lendingPool, share);
        } else {
            addCollateral(positionId, lendingPool, share);
        }

        //!QUI CI VA IL CONTROLLO DEL MARGINE E SE È SICURO PRENDERE UN PRESTITO

        uint256 usdtInBalance = USDT.balanceOf(address(this));

   

        uint256 _debtShares = borrow(
            positionId,
            borrowLeningPool,
            _amountBorrow,
            address(this)
        );
        debtUSDTShares += _debtShares;

        address[] memory path = new address[](2);
        path[0] = address(USDT);
        path[1] = address(WMNT);

        console.log("Sono arrivato qui 2!");


        console.log("Quanti USDt ho in bilancio: ", USDT.balanceOf(address(this)));
        console.log("Quanti usdt voglio vendere? ", _amountBorrow);

        uint256 amountMNTlong = _swapExactTokensForTokens(
            LBRouter,
            _amountBorrow,
            address(USDT),
            minMntToBuy,
            path,
            address(this),
            deadline
        );

        //require(
        //    USDT.balanceOf(address(this)) >= usdtInBalance + _amountBorrow,
        //    "TradingContract: Borrow didn't succeed."
        //);

        LongOp memory newLong = LongOp({
            isOpen: true,
            entryTime: uint16(block.timestamp),
            exitTime: 0,
            entryPrice: entryPrice,
            exitPrice: exitPrice,
            amountMntSell: amountMNTlong,
            amountUSDTtoBuy: _amountBorrow,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            result: 0
        });

        longOps[actualCount] = newLong;

        success = true;
    }

    function _longClose(
        uint256 indexOp,
        uint256 deadline
    ) internal returns (bool success) {
        LongOp storage closingOP = longOps[indexOp];
        require(
            closingOP.isOpen,
            "TradingContract: Long operation already closed."
        );

        closingOP.isOpen = false;
        closingOP.exitTime = uint16(block.timestamp);

        address[] memory path = new address[](2);
        path[0] = address(WMNT);
        path[1] = address(USDT);

        //!! qui pero devo capire prima quanto ripagare, se ho guadagnato devo conservare gli MNT in più.
        //? faccio ora lo swap da MNT a USDT
        uint256 usdtReceiver = _swapExactTokensForTokens(
            LBRouter,
            closingOP.amountMntSell,
            address(WMNT),
            1, //!! PER ORA VA BENE COSI MA DECO CALCOLARE LO SLIPAGE SE NO ADDIO
            path,
            address(this),
            deadline
        );

        //! sta storia del prezzo va vista costruita bene
        closingOP.exitPrice = uint256(
            getChainlinkDataFeedLatestAnswer() * 1e10
        );

        //! DEVO PERO ANCORA CHIUDERE LA POSIZIONE E RIPAGARE IL DEBITO
        uint256 _debtUSDTShares = 0; //! qui va capito come reperire il dato
        debtUSDTShares -= debtUSDTShares;

        //? 1.  Ripago il debito
        //! Va capito bene come far funzionare il burnTo , quanto share ripago in base a quanti USDT ripago?
        uint256 repaidDebt = repay(
            positionId,
            lendingPool,
            address(USDT),
            _debtUSDTShares
        );

        success = true;
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

    function openLongOp(
        uint256 _amountColl,
        uint256 _amountBorrow,
        uint256 stopLoss,
        uint256 takeProfit,
        uint256 minMntToBuy,
        uint256 entryPrice,
        uint256 exitPrice,
        uint256 deadline
    ) external {
        _longOP(
            _amountColl,
            _amountBorrow,
            stopLoss,
            takeProfit,
            deadline,
            minMntToBuy,
            entryPrice,
            exitPrice
        );
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
