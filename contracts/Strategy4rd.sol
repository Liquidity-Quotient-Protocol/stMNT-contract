// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.12;

import {console} from "forge-std/Test.sol";

import {BaseStrategy} from "@yearnvaults/contracts/BaseStrategy.sol";
import {Address} from "@openzeppelin-contract@5.3.0/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin-contract@5.3.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contract@5.3.0/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC20 as IERC20v4} from "@openzeppelin-contracts@4.5.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20 as SafeERC20v4} from "@openzeppelin-contracts@4.5.0/contracts/token/ERC20/utils/SafeERC20.sol";

import {PriceLogic} from "./TradingOp/ChainlinkOp.sol";
import {Iinit} from "./DefiProtocol/InitProt.sol";
import {ILendingPool} from "./interface/IInitCore.sol";
import {MoeContract} from "./TradingOp/SwapOperation.sol";

contract Strategy3rd is BaseStrategy, PriceLogic, Iinit, MoeContract {
    using SafeERC20 for IERC20;
    using SafeERC20v4 for IERC20v4;
    using Address for address;

    /// @notice Immutable address of the Init protocol's core/router contract.
    address public constant _initAddr =
        0x972BcB0284cca0152527c4f70f8F689852bCAFc5;
    /// @notice Immutable address of the WMNT (Wrapped MNT) token, the 'want' token for this strategy.
    address public constant WMNT = 0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8;

    /// @notice Address of the Init Protocol lending pool where funds are deposited
    /// @dev Must be set by authorized users via setLendingPool() before strategy can function
    address public lendingPool;

    address public constant router = 0xEfB43E833058Cd3464497e57428eFb00dB000763; // Merchant Moe router (LoopingHook)
    address public constant pair = 0x5d54d430D1FD9425976147318E6080479bffC16D; // MNT/USDe LB Pair

    address internal constant LBRouter =
        0xEfB43E833058Cd3464497e57428eFb00dB000763; // Merchant Moe LBRouter

    address internal poolSwap = 0x2bd5E1C8F9f2d2fA2cDdF2C4C8DAc1B8D907C3f5;

    /// @notice Address of the Init Protocol lending pool where funds are deposited
    /// @dev Must be set by authorized users via setLendingPool() before strategy can function
    uint256 private balanceShare;

    constructor(
        address _vault,
        address _priceFeedAddress
    ) BaseStrategy(_vault) PriceLogic(_priceFeedAddress) Iinit(_initAddr) {}

    function updateUnlimitedSpending(bool _approve) external onlyAuthorized {
        if (_approve) {
            SafeERC20v4.safeApprove(IERC20v4(want), address(vault), 0);
            SafeERC20v4.safeApprove(
                IERC20v4(want),
                address(vault),
                type(uint256).max
            );
        } else {
            SafeERC20v4.safeApprove(IERC20v4(want), address(vault), 0);
        }
    }

    /**
     * @notice Returns the display name of this strategy
     * @return The human-readable name of the strategy
     */
    function name() external view override returns (string memory) {
        return "Strategy Trading AI agent";
    }

    //! Allora  qui non deve la strategia investire in automatico, ma deve essere l'AI agent a decidere

    function _longOP() internal returns (bool success) {
        //! per fare long, devo depositare MNT, prendere in prestito USD e swapparli in MNT
        // Todo : Capire dove depositare MNT per prendere USD a buon mercato, e gestire il debito e capire quanto ho in valore di MNT per il shanity check
    }

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

    function _shortOpen(
        uint256 entryPrice,
        uint256 exitPrice,
        uint256 amountMntSell,
        uint256 minUsdtToBuy,
        uint256 stopLoss,
        uint256 takeProfit
    ) internal returns (bool success) {
        //! per fare short, devo venedere MNT, e prendere usd , questi li posso poi depositare per prendere yield
        // Todo : Abbastanza semplice vendere MNT, capire dove depositatare questi USD per prendere Yield

        uint256 actualCount = shortOpCounter;
        shortOpCounter += 1;

        //? devo innanzitutto capire se ho abbastanza MNT da vendere
        require(
            want.balanceOf(address(this)) >= amountMntSell,
            "Strategy3rd: Not enough MNT to sell for short."
        );

        //! DEVO CAPIRE COME GESTIRE IL DEBITO DELLA STRATEGIA NEI CONFRONTI DELLA VAULT

    

 

        return true;
    }



    function _shortClose(uint256 indexOp) internal returns( bool success){
        ShortOp storage closingOP = shortOps[indexOp];
        require(closingOP.isOpen, "Strategy3rd: Short operation already closed.");

        closingOP.isOpen = false;
        closingOP.exitTime = uint16(block.timestamp);



        closingOP.exitPrice = uint256(getChainlinkDataFeedLatestAnswer()*1e10);

        return true;



    }








    function _investInStrategy(
        uint256 _amount
    ) internal returns (bool success) {}

    function estimatedTotalAssets()
        public
        view
        override
        returns (uint256 deposited)
    {}

    function prepareReturn(
        uint256 _debtOutstanding
    )
        internal
        override
        returns (uint256 _profit, uint256 _loss, uint256 _debtPayment)
    {}

    function adjustPosition(uint256 _debtOutstanding) internal override {}

    function liquidatePosition(
        uint256 _amountNeeded
    ) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {}

    function liquidateAllPositions() internal override returns (uint256) {
        bool success = _totalRecall();
        require(success, "Strategy1st: Total recall failed.");
        return want.balanceOf(address(this));
    }

    /**
     * @notice Prepares the strategy for migration to a new strategy contract
     * @dev Liquidates all assets into want tokens to facilitate smooth migration
     * @param _newStrategy The address of the new strategy contract (unused in current implementation)
     */
    function prepareMigration(address _newStrategy) internal override {
        _totalRecall();
    }

    /**
     * @notice Specifies ERC20 tokens managed by this strategy that should be protected from vault sweep operations
     * @dev Currently returns an empty array as balanceShare represents internal pool shares, not distinct ERC20 tokens
     *      Want tokens and vault shares are automatically protected by BaseStrategy
     * @return tokens Array of protected token addresses (currently empty)
     */
    function protectedTokens()
        internal
        view
        override
        returns (address[] memory tokens)
    {
        tokens = new address[](0);
    }

    /**
     * @notice Converts an amount from the native gas token's smallest unit (wei) to want tokens
     * @dev Assumes a 1:1 value relationship since want token (WMNT) is the wrapped native token
     *      Used by Yearn infrastructure and keepers to price gas costs relative to strategy returns
     * @param _amtInWei The amount in wei (native gas token)
     * @return The equivalent amount in want tokens
     */
    function ethToWant(
        uint256 _amtInWei
    ) public view virtual override returns (uint256) {
        return _amtInWei;
    }

    /**
     * @notice Internal function to calculate profit/loss based on current assets vs debt to vault
     * @dev Compares current total assets with the strategy's debt recorded in the vault
     *      Used during performance reporting to determine strategy effectiveness
     * @return profit_ Calculated profit since last report
     * @return loss_ Calculated loss since last report
     * @return debtPayment_ Always returns 0 as actual debt payment is calculated in prepareReturn
     */
    function _returnDepositPlatformValue()
        internal
        view
        returns (uint256 profit_, uint256 loss_, uint256 debtPayment_)
    {
        uint256 prevDebt = vault.strategies(address(this)).totalDebt;
        uint256 currentAssets = estimatedTotalAssets();

        if (currentAssets > prevDebt) {
            profit_ = currentAssets - prevDebt;
            loss_ = 0;
        } else {
            loss_ = prevDebt - currentAssets;
            profit_ = 0;
        }
        debtPayment_ = 0;
    }

    function _withdrawSingleAmount(
        uint256 _amount
    ) internal returns (uint256 returnAmount_, uint256 loss_) {}

    function _totalRecall() internal returns (bool success) {
        uint256 lockedAmount = estimatedTotalAssets();

        success = true;
    }

    function getCurrentDebtValue() external view returns (uint256) {
        return 0;
    }

    function getEmergencyExitFlag() external view returns (bool) {
        return emergencyExit;
    }

    receive() external payable {}
}
