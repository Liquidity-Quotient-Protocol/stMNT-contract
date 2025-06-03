// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

pragma solidity ^0.8.12;
pragma experimental ABIEncoderV2;
import {console} from "forge-std/Test.sol";
// These are the core Yearn libraries
import {BaseStrategy, StrategyParams} from "@yearnvaults/contracts/BaseStrategy.sol";

import {Address} from "@openzeppelin-contract@5.3.0/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin-contract@5.3.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contract@5.3.0/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC20 as IERC20v4} from "@openzeppelin-contracts@4.5.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20 as SafeERC20v4} from "@openzeppelin-contracts@4.5.0/contracts/token/ERC20/utils/SafeERC20.sol";

import {Iinit} from "./DefiProtocol/InitProt.sol";
import {IInitCore} from "./interface/IInitCore.sol";
import {IInitCore, ILendingPool} from "./interface/IInitCore.sol";

import {Ownable} from "@openzeppelin-contract@5.3.0/contracts/access/Ownable.sol";

contract Strategy1st is BaseStrategy, Iinit, Ownable {
    using SafeERC20 for IERC20;
    using SafeERC20v4 for IERC20v4;
    using Address for address;

    address public immutable _initAddr =
        0x972BcB0284cca0152527c4f70f8F689852bCAFc5;
    address public immutable WMNT = 0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8;
    address public lendingPool; //0x44949636f778fAD2b139E665aee11a2dc84A2976
    uint private balanceShare;

    // solhint-disable-next-line no-empty-blocks
    constructor(
        address _vault,
        address _owner
    ) BaseStrategy(_vault) Iinit(_initAddr) Ownable(_owner) {}

    // Funzioni per la gestione della strategia
    /**
     * @notice Sets the address of the Init lending pool used by the strategy.
     * @param _lendingPool Address of the lending pool contract.
     */
    function setLendingPool(address _lendingPool) external onlyOwner {
        require(_lendingPool != address(0), "Set correct Address");
        lendingPool = _lendingPool;
    }

    //Aggiornamento spesa manuale
    /**
     * @notice Updates unlimited spending allowance for the vault on the `want` token.
     * @param _approve If true, grants max allowance; otherwise revokes.
     */
    function updateUnlimitedSpending(bool _approve) external onlyOwner {
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
     * @notice Updates unlimited spending allowance for Init on the `want` token.
     * @param _approve If true, grants max allowance; otherwise revokes.
     */
    function updateUnlimitedSpendingInit(bool _approve) external onlyOwner {
        if (_approve) {
            SafeERC20v4.safeApprove(IERC20v4(want), address(vault), 0);
            SafeERC20v4.safeApprove(
                IERC20v4(want),
                _initAddr,
                type(uint256).max
            );
        } else {
            SafeERC20v4.safeApprove(IERC20v4(want), _initAddr, 0);
        }
    }

    function approveLendingPool() external onlyOwner {
        SafeERC20v4.safeApprove(IERC20v4(want), lendingPool, 0);
        SafeERC20v4.safeApprove(IERC20v4(want), lendingPool, type(uint256).max);
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************
    /**
     * @notice Returns the strategy name.
     * @return The strategy's display name.
     */
    function name() external view override returns (string memory) {
        // Add your own name here, suggestion e.g. "StrategyCreamYFI"
        return "Strategy StMantle defi steaking";
    }

    /**
     * @notice Estimates the total assets held by the strategy in terms of `want`.
     * @return The estimated total value of managed assets.
     */
    function estimatedTotalAssets() public view override returns (uint256) {
        //? Build a more accurate estimate using the value of all positions in terms of `want`

        require(
            balanceShare == ILendingPool(lendingPool).balanceOf(address(this)),
            "Balance share mismatch"
        );

        uint _amountInShare = ILendingPool(lendingPool).toAmt(balanceShare);

        uint wantBal = want.balanceOf(address(this));
        return wantBal + _amountInShare;
    }

    /**
     * @notice Prepares performance report data for the vault.
     * @param _debtOutstanding Amount needed to be made available to the vault.
     * @return _profit Reported profit.
     * @return _loss Reported loss.
     * @return _debtPayment Amount repaid to the vault.
     */
    function prepareReturn(
        uint256 _debtOutstanding
    )
        internal
        override
        returns (uint256 _profit, uint256 _loss, uint256 _debtPayment)
    // solhint-disable-next-line no-empty-blocks
    {
        // TODO: Do stuff here to free up any returns back into `want`
        // NOTE: Return `_profit` which is value generated by all positions, priced in `want`
        // NOTE: Should try to free up at least `_debtOutstanding` of underlying position
        uint256 _balanceInContract = want.balanceOf(address(this)); // vedo quanti token liberi  ho nella contratto della strategia
        ILendingPool(lendingPool).accrueInterest();
        (_profit, _loss, _debtPayment) = _returnDepositPlatformValue();

        if (want.balanceOf(address(this)) < _profit) {
            uint256 _amountNeeded = _profit - want.balanceOf(address(this));
            (uint256 liquidated, uint256 loss) = liquidatePosition(
                _amountNeeded
            );
            _loss += loss;
        }
        if (_profit > 0) {
            _profit = _profit - 1; // arrotondo per evitare problemi di precisione
        }
        // QUI SEMPLICEMENTE CONTROLLO SE CI SONO DA PRELEVARE FONDI E AGGIORNI DATI DEL REPORT .
    }

    // solhint-disable-next-line no-empty-blocks
    /**
     * @notice Adjusts the strategy's position by depositing available funds into Init.
     * @param _debtOutstanding Amount that may be withdrawn in the next harvest.
     */
    function adjustPosition(uint256 _debtOutstanding) internal override {
        // TODO: Do something to invest excess `want` tokens (from the Vault) into your positions
        // NOTE: Try to adjust positions so that `_debtOutstanding` can be freed up on *next* harvest (not immediately)

        uint256 _balanceInContract = want.balanceOf(address(this)); // vedo quanti token liberi  ho nella contratto della strategia

        if (_balanceInContract > _debtOutstanding) {
            uint256 _amountToInvest = _balanceInContract - _debtOutstanding; // calcolo quanto posso investire
            bool success = _investInStrategy(_amountToInvest); // investo i fondi nella strategia
            require(success, "Error in invest");
        }

        //altrimenti niente ci teniamo i fondi liquidi
    }

    /**
     * @notice Attempts to free up enough capital to satisfy a withdrawal.
     * @param _amountNeeded Amount to be withdrawn from the strategy.
     * @return _liquidatedAmount Actual amount withdrawn.
     * @return _loss Any incurred loss during withdrawal.
     */
    function liquidatePosition(
        uint256 _amountNeeded
    ) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {
        uint256 balance = want.balanceOf(address(this));
        if (balance >= _amountNeeded) {
            return (_amountNeeded, 0);
        }

        uint256 amountToWithdraw = _amountNeeded - balance;
        uint256 amountFreed = _withdrawTokenFromStrategy(amountToWithdraw);

        _liquidatedAmount = balance + amountFreed;
        if (_liquidatedAmount < _amountNeeded) {
            _loss = _amountNeeded - _liquidatedAmount;
        }
    }

    /**
     * @notice Attempts to exit all positions and retrieve funds.
     * @return The total amount recovered to the strategy contract.
     */
    function liquidateAllPositions() internal override returns (uint256) {
        // TODO: Liquidate all positions and return the amount freed.
        bool success = _totalRecall();
        require(success, "Error in total recall");
        return want.balanceOf(address(this));
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary
    // solhint-disable-next-line no-empty-blocks
    /**
     * @notice Prepares the strategy for migration to a new contract.
     * @param _newStrategy Address of the new strategy contract.
     */
    function prepareMigration(address _newStrategy) internal override {
        // TODO: Transfer any non-`want` tokens to the new strategy
        // NOTE: `migrate` will automatically forward all `want` in this strategy to the new one
        //! PER ORA NON POSSO PREVEDERLO QUINDI DIREI CHE LO LASCIO VUOTO.
    }

    // Override this to add all tokens/tokenized positions this contract manages
    // on a *persistent* basis (e.g. not just for swapping back to want ephemerally)
    // NOTE: Do *not* include `want`, already included in `sweep` below
    //
    // Example:
    //
    //    function protectedTokens() internal override view returns (address[] memory) {
    //      address[] memory protected = new address[](3);
    //      protected[0] = tokenA;
    //      protected[1] = tokenB;
    //      protected[2] = tokenC;
    //      return protected;
    //    }

    /**
     * @notice Returns a list of tokens to be protected from `sweep` operations.
     * @return tokens The list of addresses considered protected.
     */
    function protectedTokens()
        internal
        view
        override
        returns (address[] memory tokens)
    {
        tokens = new address[](1);
        tokens[0] = lendingPool;
    }

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     * @dev
     *  Care must be taken when working with decimals to assure that the conversion
     *  is compatible. As an example:
     *
     *      given 1e17 wei (0.1 ETH) as input, and want is USDC (6 decimals),
     *      with USDC/ETH = 1800, this should give back 1800000000 (180 USDC)
     *
     * @param _amtInWei The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWant(
        uint256 _amtInWei
    ) public view virtual override returns (uint256) {
        return _amtInWei;
    }

    /**
     * @notice Withdraws funds from the Init strategy.
     * @param _amount Amount to withdraw in `want`.
     * @return returnAmount Amount received.
     */
    function _withdrawTokenFromStrategy(
        uint256 _amount
    ) internal returns (uint256 returnAmount) {
        // QUI DEVO RITIRARE I FONDI DALLE VARIE PIATTAFORME DOVE LI HO DEPOSITATI
        (returnAmount, ) = _withdrawSingleAmount(_amount);
    }

    /**
     * @notice Calculates the value of the current position and liquid assets.
     * @return _profit Total estimated profit.
     * @return _loss Total estimated loss (always 0 in this strategy).
     * @return _debtPayment Available liquid `want`.
     */
    function _returnDepositPlatformValue()
        internal
        returns (uint256 _profit, uint256 _loss, uint256 _debtPayment)
    {
        uint256 prevDebt = vault.strategies(address(this)).totalDebt;

        uint256 strat_balanceShare = balanceShare; // Leggi una volta per consistenza nei log
        uint256 valueOfSharesInLP;
        if (lendingPool != address(0) && strat_balanceShare > 0) {
            valueOfSharesInLP = ILendingPool(lendingPool).toAmt(
                strat_balanceShare
            );
        } else {
            valueOfSharesInLP = 0;
        }

        uint256 currentAssetsFromFunc = estimatedTotalAssets();

        if (currentAssetsFromFunc > prevDebt) {
            _profit = currentAssetsFromFunc - prevDebt;
        } else {
            _loss = prevDebt - currentAssetsFromFunc;
        }

        _debtPayment = want.balanceOf(address(this));
    }

    /**
     * @notice Deposits funds into the Init lending market.
     * @param _amount Amount of `want` to invest.
     * @return success Whether the deposit was successful.
     */
    function _investInStrategy(
        uint256 _amount
    ) internal returns (bool success) {
        // QUI DEVO INVESTIRE I FONDI NELLE VARIE PIATTAFORME DOVE LI HO DEPOSITATI

        uint256 share = depositInit(lendingPool, WMNT, _amount, address(this));
        balanceShare += share;
        success = true;
    }

    event ProblemWithWithdrawStrategy(uint time, uint share, uint balanceShare);

    /**
     * @notice Withdraws a specific amount of `want` from Init.
     * @param _amount Amount of `want` to retrieve.
     * @return returnAmount Actual amount returned.
     * @return _loss Any loss incurred during withdrawal.
     */
    function _withdrawSingleAmount(
        uint256 _amount
    ) internal returns (uint256 returnAmount, uint256 _loss) {
        // QUI RITIRIAMO I FONDI PER L'UTENTE CHE SE NE STA ANDANDO
        uint256 share = ILendingPool(lendingPool).toShares(_amount);

        if (share > balanceShare) {
            emit ProblemWithWithdrawStrategy(
                block.timestamp,
                share,
                balanceShare
            );
            revert("ProblemWithWithdrawStrategy");
        }
        balanceShare -= share;
        returnAmount = withdrawInit(lendingPool, share, address(this));
        require(returnAmount >= (_amount * 999) / 1000, "Returned too little"); // tolleranza 0.1%

        _loss = 0;
    }

    /**
     * @notice Withdraws all assets from Init and resets position.
     * @return success Whether the recall was successful.
     */

    function _totalRecall() internal returns (bool success) {
        console.log(
            "Strategy _totalRecall: Inizio. balanceShare attuale: %s",
            balanceShare
        );

        if (balanceShare > 0) {
       
            uint256 sharesToWithdraw = balanceShare; // Decidi di prelevare tutte le quote esistenti

   
            console.log(
                "Strategy _totalRecall: Tentativo di prelievo di %s shares.",
                sharesToWithdraw
            );
            uint256 amountReceived = withdrawInit(
                lendingPool,
                sharesToWithdraw,
                address(this)
            );
            // ^ Assumendo che withdrawInit prenda (pool, sharesToBurn, recipient) e restituisca amountWant
            // e che tu abbia importato e definito correttamente withdrawInit dalla tua interfaccia Iinit.

            console.log(
                "Strategy _totalRecall: Ricevuti %s want per %s shares.",
                amountReceived,
                sharesToWithdraw
            );

            balanceShare = 0; // Azzera esplicitamente DOPO aver tentato il prelievo di tutte le quote.
            console.log("Strategy _totalRecall: balanceShare azzerato.");
        } else {
            console.log(
                "Strategy _totalRecall: Nessuna balanceShare da prelevare."
            );
        }

        success = true;
        // liquidateAllPositions() (che chiama _totalRecall) restituirà want.balanceOf(address(this))
    }

    /**
     * @notice Returns the current debt value of the shares held in the Init pool.
     * @return The amount of `want` represented by `balanceShare`.
     */
    function getCurrentDebtValue() external view returns (uint256) {
        return ILendingPool(lendingPool).debtShareToAmtStored(balanceShare);
    }

    //! TEST GETTER

    function getBalanceShare() external view returns (uint256) {
        return balanceShare;
    }

    function getEmergencyExitFlag() external view returns (bool) {
        return emergencyExit; // Se emergencyExit è public in BaseStrategy
    }
}
