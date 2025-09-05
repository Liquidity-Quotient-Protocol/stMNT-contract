// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.12;

import {console} from "forge-std/Test.sol";

import {Address} from "@openzeppelin-contract@5.3.0/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin-contract@5.3.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contract@5.3.0/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721Receiver} from "@openzeppelin-contract@5.3.0/contracts/token/ERC721/IERC721Receiver.sol";
import {AccessControl} from "@openzeppelin-contract@5.3.0/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin-contract@5.3.0/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin-contract@5.3.0/contracts/security/ReentrancyGuard.sol";

import {PriceLogic} from "./ChainlinkOp.sol";
import {MoeContract} from "../TradingOp/SwapOperation.sol";
import {Iinit} from "../DefiProtocol/InitProt.sol";

import {IInitCore, ILendingPool, IMoneyMarketHook, IPosManager} from "../interface/IInitCore.sol";

contract TradingContract is
    PriceLogic,
    MoeContract,
    Iinit,
    IERC721Receiver,
    AccessControl,
    Pausable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    using Address for address;

    error InsufficientMNT();
    error PositionAlreadyClosed();
    error SlippageTooHigh();
    error DepositFailed();
    error ShortPositionCreationFailed();
    error LongPositionCreationFailed();
    error CloseShortFailed();
    error CloseLongFailed();
    error BorrowFailed();
    error SwapFailed();

    event OpenShorPosition(
        uint256 indexed indexOp,
        uint16 entryTime,
        uint256 amountMntSell,
        uint256 amountUSDTtoBuy
    );
    event CloseShortPosition(
        uint256 indexed indexOp,
        uint16 exitTime,
        int256 result
    );
    event OpenLongPosition(
        uint256 indexed indexOp,
        uint16 entryTime,
        uint256 amountMntBought,
        uint256 amountUSDTBorrowed
    );
    event CloseLongPosition(
        uint256 indexed indexOp,
        uint16 exitTime,
        int256 result
    );

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant AI_AGENT = keccak256("AI_AGENT");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    IMoneyMarketHook private constant moneyMarketHook =
        IMoneyMarketHook(0xf82CBcAB75C1138a8F1F20179613e7C0C8337346);

    IPosManager private constant posManager =
        IPosManager(0x0e7401707CD08c03CDb53DAEF3295DDFb68BBa92);

    IERC20 private constant WMNT =
        IERC20(0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8);

    IERC20 private constant USDT =
        IERC20(0x201EBa5CC46D216Ce6DC03F6a759e8E766e956aE);

    address public constant poolSwap =
        0xB52b1F5e08c04a8c33F4C7363fa2DE23B9BC169f;

    address internal constant AgniRouter =
        0xB52b1F5e08c04a8c33F4C7363fa2DE23B9BC169f;

    address public constant _initAddr =
        0x972BcB0284cca0152527c4f70f8F689852bCAFc5;

    address public lendingPool;

    address public borrowLeningPool;

    uint256 private balanceShare;

    struct LongOp {
        bool isOpen;
        uint16 entryTime;
        uint16 exitTime;
        uint256 posID; // position ID in Init
        uint256 entryPrice;
        uint256 exitPrice;
        uint256 amountMntBought; // MNT comprati con leva (ex amountMntSell)
        uint256 amountUSDTBorrowed; // USDT presi in prestito (ex amountUSDTtoBuy)
        uint256 collateralShares; // ✅ AGGIUNTO: shares di collaterale depositate
        uint256 debtUSDTShares; // shares di debito USDT
        uint256 stopLoss;
        uint256 takeProfit;
        int256 result; //in MNT
    }

    uint256 private longOpCounter;
    uint256 private debtUSDTShares;

    mapping(uint256 => LongOp) private longOps;

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

    constructor(
        address _priceFeedAddress
    ) PriceLogic(_priceFeedAddress) Iinit(_initAddr) {
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(GUARDIAN_ROLE, msg.sender);
        _grantRole(AI_AGENT, msg.sender);

        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(GUARDIAN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(AI_AGENT, ADMIN_ROLE);

        // Approve max tokens for router and INIT
        WMNT.approve(AgniRouter, type(uint256).max);
        USDT.approve(AgniRouter, type(uint256).max);
        WMNT.approve(INIT_CORE, type(uint256).max);
        USDT.approve(INIT_CORE, type(uint256).max);
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Not an admin");
        _;
    }
    modifier onlyAuthorized() {
        require(
            hasRole(ADMIN_ROLE, msg.sender) ||
                hasRole(GUARDIAN_ROLE, msg.sender),
            "Not authorized"
        );
        _;
    }

    modifier onlyAIAgent() {
        require(hasRole(AI_AGENT, msg.sender), "Not an AI agent");
        _;
    }
    modifier onlyAiOrGuardian() {
        require(
            hasRole(AI_AGENT, msg.sender) || hasRole(GUARDIAN_ROLE, msg.sender),
            "Not authorized"
        );
        _;
    }

    function getShortOpCounter() external view returns (uint256) {
        return shortOpCounter;
    }

    function getLongOpCounter() external view returns (uint256) {
        return longOpCounter;
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

    function setLendingPool(address _lendingPool) external onlyAdmin {
        require(
            _lendingPool != address(0),
            "Strategy1st: Invalid LendingPool address."
        );
        lendingPool = _lendingPool;
    }

    function setBorrowLendingPool(address _lendingPool) external onlyAdmin {
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
        uint256 stopLoss,
        uint256 takeProfit
    ) external onlyAIAgent returns (bool success) {
        success = _shortOpen(
            entryPrice,
            exitPrice,
            amountMntSell,
            minUsdtToBuy,
            stopLoss,
            takeProfit
        );
        if (!success) {
            revert ShortPositionCreationFailed();
        }
        emit OpenShorPosition(
            shortOpCounter - 1,
            uint16(block.timestamp),
            amountMntSell,
            minUsdtToBuy
        );
    }

    function executeShortClose(
        uint256 indexOp,
        uint256 amountOutMin
    ) external onlyAiOrGuardian returns (bool success, int256 profitLoss) {
        (success, profitLoss) = _shortClose(indexOp, amountOutMin);
        if (!success) {
            revert CloseShortFailed();
        }
        emit CloseShortPosition(indexOp, uint16(block.timestamp), profitLoss);
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
        uint256 actualCount = shortOpCounter;
        shortOpCounter += 1;

        if (WMNT.balanceOf(address(this)) < amountMntSell) {
            revert InsufficientMNT();
        }

        address[] memory path = new address[](2);
        path[0] = address(WMNT);
        path[1] = address(USDT);

        uint256 usdReceiver = _swapExactTokensForTokens(
            AgniRouter,
            amountMntSell,
            address(WMNT),
            minUsdtToBuy,
            path,
            address(this)
        );
        if (usdReceiver == 0) {
            revert SwapFailed();
        }

        if (usdReceiver < minUsdtToBuy) {
            revert SlippageTooHigh();
        }

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
        uint256 minOutAmount
    ) internal returns (bool success, int256 profitLoss) {
        ShortOp storage closingOP = shortOps[indexOp];
        if (!closingOP.isOpen) {
            revert PositionAlreadyClosed();
        }

        closingOP.isOpen = false;
        closingOP.exitTime = uint16(block.timestamp);

        address[] memory path = new address[](2);
        path[0] = address(USDT);
        path[1] = address(WMNT);

        uint256 mntReceiver = _swapExactTokensForTokens(
            AgniRouter,
            closingOP.amountUSDTtoBuy,
            address(USDT),
            minOutAmount,
            path,
            address(this)
        );

        if (mntReceiver < minOutAmount) {
            revert SlippageTooHigh();
        }

        if (mntReceiver == 0) {
            revert SwapFailed();
        }

        closingOP.exitPrice = uint256(
            getChainlinkDataFeedLatestAnswer() * 1e10
        );

        if (mntReceiver >= closingOP.amountMntSell) {
            closingOP.result = int256(mntReceiver - closingOP.amountMntSell);
            profitLoss = closingOP.result;
        } else {
            closingOP.result = -int256(closingOP.amountMntSell - mntReceiver);
            profitLoss = closingOP.result;
        }

        success = true;
    }

    //*---------------------------------------------------------------------

    //*------------------------------ LONG OPERATIONS --------------------

    function openLongOp(
        uint256 _amountColl,
        uint256 _amountBorrow,
        uint256 stopLoss,
        uint256 takeProfit,
        uint256 minMntToBuy,
        uint256 entryPrice,
        uint256 exitPrice
    ) external onlyAIAgent returns (bool success) {
        success = _longOP(
            _amountColl,
            _amountBorrow,
            stopLoss,
            takeProfit,
            minMntToBuy,
            entryPrice,
            exitPrice
        );
        if (!success) {
            revert LongPositionCreationFailed();
        }
        emit OpenLongPosition(
            longOpCounter - 1,
            uint16(block.timestamp),
            _amountColl,
            _amountBorrow
        );
    }

    function closeLongOp(
        uint256 indexOp,
        uint256 deadline
    ) external onlyAiOrGuardian returns (bool success, int256 profitLoss) {
        (success, profitLoss) = _longClose(indexOp, deadline);
        if (!success) {
            revert CloseLongFailed();
        }
        emit CloseLongPosition(indexOp, uint16(block.timestamp), profitLoss);
    }

    uint256 private balanceshare;

    function _depositMNTforUSD(
        uint256 _amount
    ) internal returns (bool success, uint256 share) {
        share = depositInit(lendingPool, address(WMNT), _amount, address(this));
        balanceshare += share;
        success = true;
    }

    function _createInitPosition()
        internal
        returns (bool success, uint256 posId)
    {
        uint16 mode = 1; // 1 = isolated, 2 = cross
        posId = createInitPosition(mode, address(this));
        success = true;
    }

    function _repayDebtUSD(
        uint256 _amount,
        uint256 positionId
    ) internal returns (uint256 repaidAmount) {
        repaidAmount = repay(
            positionId,
            borrowLeningPool,
            address(USDT),
            _amount
        );
    }

    function _removeWmntCollateral(
        uint256 _shares,
        uint256 positionId
    ) internal returns (bool success) {
        removeCollateral(positionId, borrowLeningPool, _shares, address(this));
        success = true;
    }

    function _longOP(
        uint256 _amountColl,
        uint256 _amountBorrow,
        uint256 stopLoss,
        uint256 takeProfit,
        uint256 minMntToBuy,
        uint256 entryPrice,
        uint256 exitPrice
    ) internal returns (bool success) {
        if (WMNT.balanceOf(address(this)) < _amountColl) {
            revert InsufficientMNT();
        }

        uint256 actualCount = longOpCounter;
        longOpCounter += 1;

        // Approva WMNT per MoneyMarketHook
        WMNT.approve(address(moneyMarketHook), _amountColl);

        // Costruisci parametri per MoneyMarketHook
        IMoneyMarketHook.DepositParams[]
            memory depositParams = new IMoneyMarketHook.DepositParams[](1);
        depositParams[0] = IMoneyMarketHook.DepositParams({
            pool: lendingPool,
            amt: _amountColl,
            rebaseHelperParams: IMoneyMarketHook.RebaseHelperParams(
                address(0),
                address(0)
            )
        });

        IMoneyMarketHook.BorrowParams[]
            memory borrowParams = new IMoneyMarketHook.BorrowParams[](1);
        borrowParams[0] = IMoneyMarketHook.BorrowParams({
            pool: borrowLeningPool,
            amt: _amountBorrow,
            to: address(this)
        });

        IMoneyMarketHook.OperationParams memory params = IMoneyMarketHook
            .OperationParams({
                posId: 0, // 0 = crea nuova posizione
                viewer: address(this),
                mode: 1, // isolated mode
                depositParams: depositParams,
                withdrawParams: new IMoneyMarketHook.WithdrawParams[](0),
                borrowParams: borrowParams,
                repayParams: new IMoneyMarketHook.RepayParams[](0),
                minHealth_e18: 1.2e18, // Min 120% health factor per sicurezza
                returnNative: false
            });

        // Esegui operazione atomica: deposit + collateralize + borrow
        (
            uint256 posId,
            uint256 initPosId,
            bytes[] memory results
        ) = moneyMarketHook.execute(params);

        if (initPosId == 0) {
            revert LongPositionCreationFailed();
        }

        // Verifica che abbiamo ricevuto gli USDT
        uint256 usdtBalance = USDT.balanceOf(address(this));
        if (usdtBalance < _amountBorrow) {
            revert BorrowFailed();
        }

        // Swappa USDT → MNT
        address[] memory path = new address[](2);
        path[0] = address(USDT);
        path[1] = address(WMNT);

        uint256 amountMNTBought = _swapExactTokensForTokens(
            AgniRouter,
            _amountBorrow,
            address(USDT),
            minMntToBuy,
            path,
            address(this)
        );

        if (amountMNTBought < minMntToBuy) {
            revert SlippageTooHigh();
        }
        if (amountMNTBought == 0) {
            revert SwapFailed();
        }

        // Ottieni debt shares dalla posizione (invece di tracciare manualmente)
        (address[] memory debtPools, uint[] memory debtShares) = posManager
            .getPosBorrInfo(initPosId);
        uint256 _debtShares = debtShares.length > 0 ? debtShares[0] : 0;

        // Ottieni collateral shares dalla posizione
        (address[] memory collPools, uint[] memory collAmts, , , ) = posManager
            .getPosCollInfo(initPosId);
        uint256 collateralShares = collAmts.length > 0 ? collAmts[0] : 0;

        LongOp memory newLong = LongOp({
            isOpen: true,
            entryTime: uint16(block.timestamp),
            posID: initPosId, // Usa initPosId, non posId
            exitTime: 0,
            entryPrice: entryPrice,
            exitPrice: exitPrice,
            amountMntBought: amountMNTBought,
            amountUSDTBorrowed: _amountBorrow,
            collateralShares: collateralShares,
            debtUSDTShares: _debtShares,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            result: 0
        });

        longOps[actualCount] = newLong;
        success = true;
    }

    function _calcGainOrLoss(
        uint256 _amountMNT,
        uint256 _usdDebt
    ) internal returns (int256) {
        int256 price = getChainlinkDataFeedLatestAnswer();

        // MI SERVE SAPERE A QUINTI USD CORRISPONDONO GLI MNT CHE HO
        uint256 valueInUSD = (_amountMNT * uint256(price)) / 1e18;
        // ora ho il valore in USD di quegli MNT
        // lo confronto con il debito in USD che ho

        if (valueInUSD >= _usdDebt) {
            // ho guadagnato
            int256 gain = int256(valueInUSD - _usdDebt);
            // ora devo convertire il guadagno in MNT
            int256 gainInMNT = (gain * 1e18) / int256(price);
            return gainInMNT;
        } else {
            // ho perso
            int256 loss = int256(_usdDebt - valueInUSD);
            int256 lossInMNT = (loss * 1e18) / int256(price);
            return -lossInMNT;
        }
    }

    function _longClose(
        uint256 indexOp,
        uint256 amountOutMin
    ) internal returns (bool success, int256 profitLoss) {
        LongOp storage closingOP = longOps[indexOp];
        if (!closingOP.isOpen) {
            revert PositionAlreadyClosed();
        }

        closingOP.isOpen = false;
        closingOP.exitTime = uint16(block.timestamp);

        // 1. CALCOLA QUANTO USDT SERVONO PER RIPAGARE IL DEBITO
        uint256 debtShares = closingOP.debtUSDTShares;
        uint256 usdtAmountToRepay = ILendingPool(borrowLeningPool)
            .debtShareToAmtCurrent(debtShares);

        // 2. CALCOLA MNT DA VENDERE PER OTTENERE QUEGLI USDT
        int256 currentPrice = getChainlinkDataFeedLatestAnswer();
        uint256 mntNeededForDebt = (usdtAmountToRepay * 1e18) /
            uint256(currentPrice);
        mntNeededForDebt = (mntNeededForDebt * 1050) / 1000; // +5% buffer

        // 3. VENDI MNT PER OTTENERE USDT
        address[] memory path = new address[](2);
        path[0] = address(WMNT);
        path[1] = address(USDT);

        uint256 usdtReceived = _swapExactTokensForTokens(
            AgniRouter,
            mntNeededForDebt,
            address(WMNT),
            amountOutMin,
            path,
            address(this)
        );
        // 4. RIPAGA IL DEBITO USDT
        USDT.approve(INIT_CORE, usdtAmountToRepay); // ! poi devo passare a safe approve
        uint256 repaidAmount = repay(
            closingOP.posID,
            borrowLeningPool,
            address(USDT),
            debtShares
        );

        // 5. RIMUOVI IL COLLATERALE USANDO LE SHARES CORRETTE
        removeCollateral(
            closingOP.posID,
            lendingPool,
            closingOP.collateralShares,
            address(this)
        );

        // 6. PRELEVA IL COLLATERALE ORIGINALE
        uint256 withdrawnAmount = withdrawInit(
            lendingPool,
            closingOP.collateralShares, // ✅ USA COLLATERAL SHARES, NON DEBT SHARES
            address(this)
        );

        // 7. CALCOLA PROFIT/LOSS CORRETTO
        uint256 totalMNTRecovered = withdrawnAmount +
            (closingOP.amountMntBought - mntNeededForDebt);
        // Il collaterale originale era l'ammontare depositato inizialmente
        uint256 originalCollateral = (closingOP.collateralShares * 1e18) / 1e18; // Conversione approssimativa

        if (totalMNTRecovered >= originalCollateral) {
            closingOP.result = int256(totalMNTRecovered - originalCollateral);
            profitLoss = closingOP.result;
        } else {
            closingOP.result = -int256(originalCollateral - totalMNTRecovered);
            profitLoss = closingOP.result;
        }

        // 8. AGGIORNA TRACKING GLOBALI
        debtUSDTShares -= closingOP.debtUSDTShares;
        balanceshare -= closingOP.collateralShares;

        closingOP.exitPrice = uint256(currentPrice * 1e10);

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
        if (amount > mntBalance) {
            revert InsufficientMNT();
        }
        WMNT.transfer(msg.sender, amount);
        mntBalance -= amount;
    }

    // Aggiungi questa funzione view per monitoraggio posizioni
    function checkLongPositionHealth(
        uint256 indexOp
    )
        external
        view
        returns (uint256 healthFactor, bool isHealthy, bool nearLiquidation)
    {
        LongOp storage op = longOps[indexOp];
        require(op.isOpen, "Position closed");

        // Ottieni debt e collateral dalla posizione Init
        (address[] memory debtPools, uint[] memory debtShares) = posManager
            .getPosBorrInfo(op.posID);
        (address[] memory collPools, uint[] memory collAmts, , , ) = posManager
            .getPosCollInfo(op.posID);

        if (debtShares.length == 0 || collAmts.length == 0) {
            return (type(uint256).max, true, false);
        }

        // Calcola valori attuali
        uint256 debtValue = ILendingPool(borrowLeningPool).debtShareToAmtStored(
            debtShares[0]
        );
        uint256 collValue = (collAmts[0] *
            uint256(getChainlinkDataFeedLatestAnswer())) / 1e18;

        healthFactor = (collValue * 1e18) / debtValue;
        isHealthy = healthFactor > 1e18; // > 100%
        nearLiquidation = healthFactor < 1.1e18; // < 110%
    }

    // Funzione per ottenere tutte le posizioni long aperte
    function getOpenLongPositions()
        external
        view
        returns (uint256[] memory openPositions)
    {
        uint256 count = 0;
        for (uint256 i = 0; i < longOpCounter; i++) {
            if (longOps[i].isOpen) count++;
        }

        openPositions = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < longOpCounter; i++) {
            if (longOps[i].isOpen) {
                openPositions[index++] = i;
            }
        }
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
