// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IInitCore, ILendingPool} from "../interface/IInitCore.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


contract Iinit {
    using SafeERC20 for IERC20;

/*
    address public constant factory =
        0x972BcB0284cca0152527c4f70f8F689852bCAFc5; // InitCore (Factory)

    address internal constant INIT_CORE =
        0x972BcB0284cca0152527c4f70f8F689852bCAFc5; // InitCore

    //address internal constant LBROUTER =
    //    0xEfB43E833058Cd3464497e57428eFb00dB000763; // LoopingHook via Merchant Moe (Router per swap)

    address internal constant POS_MANAGER =
        0x0e7401707CD08c03CDb53DAEF3295DDFb68BBa92; // PosManager
*/

    IInitCore internal initCore;
    constructor(address _initCore) {
        initCore = IInitCore(_initCore);
    }

    // Deposit MNT to lending pool and receive inTokens
    function depositInit(
        address lendingPool,
        address _tokenIn,
        uint256 amount,
        address receiver
    ) internal returns (uint256 shares) {
        IERC20(_tokenIn).safeTransfer(lendingPool, amount);
        shares = initCore.mintTo(lendingPool, receiver);
    }

    // Withdraw MNT by burning inTokens
    function withdrawInit(
        address lendingPool,
        uint256 sharesToBurn,
        address receiver
    ) internal returns (uint256 amount) {
        IERC20(lendingPool).safeTransfer(lendingPool, sharesToBurn);
        amount = initCore.burnTo(lendingPool, receiver);
    }

    // Create a new position
    event PositionCreated(uint256 indexed posId, address indexed creator);

    function createInitPosition(
        uint16 mode,
        address viewer
    ) internal returns (uint256 posId) {
        posId = initCore.createPos(mode, viewer);
        emit PositionCreated(posId, msg.sender);
    }

/*
    // Add inToken as collateral to a position
    function addCollateral(
        uint256 posId,
        address lendingPool,
        uint256 shares
    ) internal {
        IERC20(lendingPool).safeTransfer(POS_MANAGER, shares);
        initCore.collateralize(posId, lendingPool);
    }

    // Remove collateral from a position
    function removeCollateral(
        uint256 posId,
        address lendingPool,
        uint256 shares,
        address receiver
    ) internal {
        initCore.decollateralize(posId, lendingPool, shares, receiver);
    }

    // Borrow underlying tokens from a position
    function borrow(
        uint256 posId,
        address lendingPool,
        uint256 amount,
        address receiver
    ) internal returns (uint256 debtShares) {
        debtShares = initCore.borrow(lendingPool, amount, posId, receiver);
    }

    // Repay borrowed tokens
    function repay(
        uint256 posId,
        address lendingPool,
        address underlyingToken,
        uint256 repayShares
    ) internal returns (uint256 repaidAmount) {
        uint256 repayAmount = ILendingPool(lendingPool).debtShareToAmtCurrent(
            repayShares
        );
        //IERC20(underlyingToken).safeApprove(INIT_CORE, repayAmount);
        IERC20(underlyingToken).approve(INIT_CORE, repayAmount);

        repaidAmount = initCore.repay(lendingPool, repayShares, posId);
    }*/
}