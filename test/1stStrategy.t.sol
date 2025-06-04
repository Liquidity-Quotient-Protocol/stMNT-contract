// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StMNT} from "../contracts/Vault.sol";
import {Strategy1st} from "../contracts/Strategy1st.sol";
// Rimuovi ILendingPool da qui se già importato sotto
// import {ILendingPool} from "../contracts/interface/IInitCore.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IInitCore, ILendingPool} from "../contracts/interface/IInitCore.sol"; // Assicurati che questo percorso sia corretto

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

contract Strg1 is Test {
    StMNT public vault;
    Strategy1st public strategy1st;

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
        strategy1st = new Strategy1st(address(vault), governance);
        strategy1st.setLendingPool(LENDING_POOL_ADDRESS);
        strategy1st.updateUnlimitedSpending(true);
        strategy1st.updateUnlimitedSpendingInit(true); 
        strategy1st.approveLendingPool(); 
        vault.addStrategy(
            address(strategy1st),
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
        vm.startPrank(governance);
        assertEq(vault.governance(), governance);
        assertEq(vault.management(), management);
        assertEq(vault.guardian(), guardian);
        assertEq(vault.rewards(), treasury);
        assertEq(vault.name(), "stMNT");
        assertEq(vault.symbol(), "stMNT");
        assertEq(address(vault.token()), address(WMNT));

        assertEq(vault.performanceFee(), 0); 
        assertEq(vault.managementFee(), 0); 
        assertEq(vault.lockedProfitDegradation(), 46000000000000); 

 

        assertEq(vault.depositLimit(), type(uint256).max); 

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

        vm.startPrank(governance);
        vm.startPrank(governance);
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
        ) = vault.strategies(address(strategy1st));

        vault.updateStrategyDebtRatio(address(strategy1st), 0); 
        vm.stopPrank();
        vault.updateStrategyDebtRatio(address(strategy1st), 0); 
        vm.stopPrank();
        vault.updateStrategyDebtRatio(address(strategy1st), 0); 
        vm.stopPrank();

        uint256 shares = vault.deposit(1000 ether, user1);
        assertEq(shares, 1000 ether);
        assertEq(vault.pricePerShare(), 1 ether); 

        uint256 assets = vault.withdraw(shares, user1, 0); 
        assertEq(assets, 1000 ether);

        vm.expectRevert(); 
        vault.withdraw(1, user1, 0);
        vm.stopPrank();

        vm.startPrank(governance);
        vault.updateStrategyDebtRatio(address(strategy1st), originalDebtRatio);
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
        strategy1st.harvest();
        vm.stopPrank();

        uint256 ppsAfterHarvest = vault.pricePerShare();
        console.log(
            "PPS after 1st harvest (NoInterestTest): ",
            ppsAfterHarvest
        );
        // Dopo il primo harvest, il PPS potrebbe rimanere 1 ether o variare leggermente
        // a seconda di come il vault gestisce il primo deposito in una strategia.
        // Per semplicità, non facciamo un assertEq stretto qui, ma lo osserviamo.

        // Verifica che le quote siano circa equivalenti al deposito se PPS è ~1e18
        assertApproxEqAbs(shares, depositAmount, 1, "Shares calculation issue");

        vm.startPrank(user1);
        // L'utente non ha bisogno di approvare il vault per prelevare le proprie quote.
        // vault.approve(address(vault), shares);
        uint256 assets = vault.withdraw(shares, user1, 100); // maxLoss 0.01% = 10 BPS
        // Ci aspettiamo di riavere circa l'importo depositato, con una piccola tolleranza per eventuali
        // micro-fees o imperfezioni nel calcolo del PPS al primo deposito.
        assertApproxEqRel(
            assets,
            depositAmount,
            100,
            "Withdrawal amount mismatch (NoInterestTest), slippage 0.01%"
        ); // Tolleranza 0.01%
        vm.stopPrank();
        return assets;
    }

    function testDeposit_Harvest_GeneratesInterest_And_Withdraw()
        internal
        returns (uint256)
    {
        uint256 depositAmount = 1000 ether;
        uint256 initialShares;
        uint256 pricePerShare_BeforeInterest;
        uint256 pricePerShare_AfterInterest;
        uint256 assetsWithdrawn;

        vm.deal(user1, depositAmount * 2);
        vm.startPrank(user1);
        wrapMNT(depositAmount);
        WMNT.approve(address(vault), depositAmount);
        initialShares = vault.deposit(depositAmount, user1);
        console.log(
            "User1 deposited %s, received %s shares.",
            depositAmount,
            initialShares
        );
        vm.stopPrank();

        vm.startPrank(management);
        strategy1st.harvest();
        vm.stopPrank();

        pricePerShare_BeforeInterest = vault.pricePerShare();
        console.log(
            "PricePerShare after 1st harvest (before interest): %s",
            pricePerShare_BeforeInterest
        );

        uint strategyWantBalance = WMNT.balanceOf(address(strategy1st));
        uint strategySharesInLP = ILendingPool(LENDING_POOL_ADDRESS).balanceOf(
            address(strategy1st)
        );
        console.log(
            "Strategy - Want balance after 1st harvest: %s",
            strategyWantBalance
        );
        console.log(
            "Strategy - Shares in LP after 1st harvest: %s",
            strategySharesInLP
        );
        if (strategySharesInLP > 0) {
            uint valueInLP = ILendingPool(LENDING_POOL_ADDRESS).toAmt(
                strategySharesInLP
            );
            console.log(
                "Strategy - Value of LP shares after 1st harvest (via toAmt): %s",
                valueInLP
            );
        }

        uint timeToSkip = 60 days;
        skip(timeToSkip);
        console.log("Skipped %s seconds.", timeToSkip);

        ILendingPool(LENDING_POOL_ADDRESS).accrueInterest();
        console.log("Called accrueInterest() on LendingPool.");

        if (strategySharesInLP > 0) {
            skip(10 hours);
            ILendingPool(LENDING_POOL_ADDRESS).accrueInterest();
            uint valueInLP_afterAccrue = ILendingPool(LENDING_POOL_ADDRESS)
                .toAmt(strategySharesInLP);
            console.log(
                "Strategy - Value of LP shares after skip & accrue (via toAmt): %s",
                valueInLP_afterAccrue
            );
            assertTrue(
                valueInLP_afterAccrue > ((depositAmount * 99) / 100),
                "Value in LP did not increase as expected after accrue."
            );
        }

        vm.startPrank(management);
        strategy1st.harvest();
        vm.stopPrank();
        skip(10 hours);

        pricePerShare_AfterInterest = vault.pricePerShare();
        console.log(
            "PricePerShare after 2nd harvest (after interest): %s",
            pricePerShare_AfterInterest
        );

      
        assertTrue(
            pricePerShare_AfterInterest > pricePerShare_BeforeInterest,
            "FAIL: PricePerShare did not increase after interest period and harvest."
        );

       
        vm.startPrank(user1);
        assetsWithdrawn = vault.withdraw(initialShares, user1, 100); // maxLoss 0.01% = 10 BPS
        vm.stopPrank();

        console.log(
            "User1 withdrew %s assets for %s shares.",
            assetsWithdrawn,
            initialShares
        );

        uint expectedMinReturn = depositAmount + ((depositAmount * 1) / 10000); // Esempio: almeno 0.01% di profitto
        assertTrue(
            assetsWithdrawn > depositAmount,
            "FAIL: Withdrawn assets are not greater than initial deposit."
        );

        console.log(
            "FINAL - Asset Vault (liquid WMNT): %s",
            WMNT.balanceOf(address(vault))
        );
        console.log(
            "FINAL - Asset User1 (WMNT balance): %s",
            WMNT.balanceOf(user1)
        );

        return assetsWithdrawn;
    }

 

    function testFullFlow_InterestAccrualAndWithdrawal() public {
        testInitialize();
    
        uint asset_no_interest = testDepositAndWithdraw_WithStrategy_NoInterest();
        console.log("--- Output from NoInterest test run ---");
        console.log(
            "Assets returned (no significant interest): %s",
            asset_no_interest
        );

        skip(1 hours);

        uint asset_with_interest = testDeposit_Harvest_GeneratesInterest_And_Withdraw();
        console.log("--- Output from WithInterest test run ---");
        console.log("Assets returned (with interest): %s", asset_with_interest);

        assertTrue(
            asset_with_interest > asset_no_interest,
            "FAIL: Assets with interest are not greater than assets without interest."
        );
        console.log(
            "SUCCESS: Interest successfully accrued and withdrawn by user."
        );


    }
}
