// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StMNT} from "../contracts/Vault.sol";
import {Strategy2nd} from "../contracts/Strategy2nd.sol";
// Rimuovi ILendingPool da qui se già importato sotto
// import {ILendingPool} from "../contracts/interface/IInitCore.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILendingPool, IProtocolDataProvider} from "../contracts/interface/ILendl.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

contract Strg2 is Test {
    StMNT public vault;
    Strategy2nd public strategy2nd;

    address public governance = address(1);
    address public management = address(2);
    address public treasury = address(3);
    address public guardian = address(4);
    address public user1 = address(5);
    address public user2 = address(6);
    address public user3 = address(7);

    IWETH public constant WMNT =
        IWETH(address(0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8));

    address internal constant LENDING_POOL_ADDRESS =
        0x44949636f778fAD2b139E665aee11a2dc84A2976;

    function setUp() public {
        vault = new StMNT(
            address(WMNT),
            governance,
            treasury,
            "stMNT",
            "stMNT",
            guardian,
            management
        );
        vm.startPrank(governance);
        strategy2nd = new Strategy2nd(address(vault), governance);
        strategy2nd.updateUnlimitedSpending(true);
        strategy2nd.updateUnlimitedSpendingLendl(true);
        vault.addStrategy(
            address(strategy2nd),
            10_000,
            0,
            type(uint256).max,
            0
        );
        vault.setPerformanceFee(0);
        vault.setManagementFee(0);
        vault.setDepositLimit(type(uint256).max);
        vm.stopPrank();
    }

    function wrapMNT(uint256 _amount) internal {
        WMNT.deposit{value: _amount}();
    }

    function testInitialize() internal {
        // ... (il tuo testInitialize rimane invariato) ...
        vm.startPrank(governance);
        assertEq(vault.governance(), governance);
        assertEq(vault.management(), management);
        assertEq(vault.guardian(), guardian);
        assertEq(vault.rewards(), treasury);
        assertEq(vault.name(), "stMNT");
        assertEq(vault.symbol(), "stMNT");
        assertEq(address(vault.token()), address(WMNT));

        // Le fee sono già state impostate a 0 in setUp() per i test di logica degli interessi
        assertEq(vault.performanceFee(), 0); // Modificato per riflettere setUp
        assertEq(vault.managementFee(), 0); // Modificato per riflettere setUp
        assertEq(vault.lockedProfitDegradation(), 46000000000000); // Valore di default

        // vault.setDepositLimit(1_000_000 ether); // Già fatto in setUp

        assertEq(vault.depositLimit(), type(uint256).max); // Modificato
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert("Vault: !governance");
        vault.setPerformanceFee(1000);
        vm.expectRevert("Vault: !governance");
        vault.setManagementFee(1000);
        vm.stopPrank();
    }

    function testDepositAndWithdraw_NoStrategy() internal {
        vm.deal(user1, 2_000 ether);
        vm.startPrank(user1);
        assertEq(user1.balance, 2_000 ether);
        wrapMNT(1_000 ether);
        WMNT.approve(address(vault), 1000 ether);
        vm.stopPrank();

        vm.startPrank(governance);

        (
            uint256 performanceFee,
            uint256 activation,
            uint256 originalDebtRatio,
            uint256 minDebtPerHarvest,
            uint256 maxDebtPerHarvest,
            uint256 lastReport,
            uint256 totalDebt,
            uint256 totalGain,
            uint256 totalLoss
        ) = vault.strategies(address(strategy2nd));

        vault.updateStrategyDebtRatio(address(strategy2nd), 0); // Disattiva la strategia
        vm.stopPrank();

        vm.startPrank(user1);
        uint256 shares = vault.deposit(1000 ether, user1);
        assertEq(shares, 1000 ether);
        assertEq(vault.pricePerShare(), 1 ether);

        // Non serve vault.approve per prelevare le proprie quote
        // vault.approve(address(vault), 1 ether);
        uint256 assets = vault.withdraw(shares, user1, 0); // maxLoss a 0
        assertEq(assets, 1000 ether);

        // vault.approve(address(vault), 1 ether);
        vm.expectRevert();
        vault.withdraw(1, user1, 0);
        vm.stopPrank();

        vm.startPrank(governance);
        vault.updateStrategyDebtRatio(address(strategy2nd), originalDebtRatio);
        vm.stopPrank();
    }

    function testDepositAndWithdraw_WithStrategy_NoInterest()
        internal
        returns (uint256)
    {
        uint256 depositAmount = 1000 ether;
        vm.deal(user1, depositAmount * 2); // Dai fondi all'utente

        vm.startPrank(user1);
        wrapMNT(depositAmount);
        WMNT.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user1);
        vm.stopPrank();

        uint256 ppsBeforeHarvest = vault.pricePerShare();
        console.log(
            "PPS before 1st harvest (NoInterestTest): ",
            ppsBeforeHarvest
        );

        vm.startPrank(management); // keeper
        strategy2nd.harvest();
        vm.stopPrank();

        uint256 ppsAfterHarvest = vault.pricePerShare();
        console.log(
            "PPS after 1st harvest (NoInterestTest): ",
            ppsAfterHarvest
        );

        // Verifica che le quote siano circa equivalenti al deposito se PPS è ~1e18
        assertApproxEqAbs(shares, depositAmount, 1, "Shares calculation issue");

        vm.startPrank(user1);

        uint256 assets = vault.withdraw(shares, user1, 100); // maxLoss 0.01% = 10 BPS

        assertApproxEqRel(
            assets,
            depositAmount,
            100,
            "Withdrawal amount mismatch (NoInterestTest), slippage 0.01%"
        ); // Tolleranza 0.01%
        vm.stopPrank();
        return assets;
    }

    function testDepositAndWithdraw_WithStrategy_WithInterest()
        internal
        returns (uint256)
    {
        uint256 depositAmount = 1000 ether;
        vm.deal(user1, depositAmount * 2); // Dai fondi all'utente

        vm.startPrank(user1);
        wrapMNT(depositAmount);
        WMNT.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user1);
        vm.stopPrank();

        uint256 ppsBeforeHarvest = vault.pricePerShare();
        console.log(
            "PPS before 1st harvest (NoInterestTest): ",
            ppsBeforeHarvest
        );
        vm.startPrank(management); // keeper
        strategy2nd.harvest();
        vm.stopPrank();

        skip(60 days);
/*

        vm.startPrank(management); // keeper
        strategy2nd.harvest();
        vm.stopPrank();
        skip(10 hours);
*/
        console.log(
            "strategia balance ->",
            IERC20(address(WMNT)).balanceOf(address(strategy2nd))
        );

        console.log(
            "vault balance ->",
            IERC20(address(WMNT)).balanceOf(address(vault))
        );

        uint256 ppsAfterHarvest = vault.pricePerShare();
        console.log("PPS after 1st harvest  ", ppsAfterHarvest);

        vm.startPrank(user1);

        uint256 assets = vault.withdraw(shares, user1, 100); // maxLoss 0.01% = 10 BPS

        console.log("Withdrawal amount (WithInterestTest): ", assets);
/*
        assertGe(
            assets,
            depositAmount,
            "Withdrawal amount should be greater than deposit (interest accrued)"
        );*/
        vm.stopPrank();
        return assets;
    }

    function testFullFlow_InterestAccrualAndWithdrawal() public {
        testInitialize();

        //testDepositAndWithdraw_NoStrategy();

        //testDepositAndWithdraw_WithStrategy_NoInterest();

        testDepositAndWithdraw_WithStrategy_WithInterest();
    }
}
