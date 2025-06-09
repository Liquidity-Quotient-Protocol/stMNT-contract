// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StMNT} from "../contracts/Vault.sol";
import {Strategy1st} from "../contracts/Strategy1st.sol";
import {Strategy2nd} from "../contracts/Strategy2nd.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IInitCore, ILendingPool as ILendingPoolInit} from "../contracts/interface/IInitCore.sol";
import {ILendingPool as ILendingPoolLendl, IProtocolDataProvider} from "../contracts/interface/ILendl.sol";

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256) external;

    function approve(address, uint256) external returns (bool);

    function transfer(address, uint256) external returns (bool);

    function balanceOf(address) external view returns (uint256);
}

contract DoppioTest is Test {
    StMNT public vault;
    Strategy1st public strategy1st;
    Strategy2nd public strategy2nd;

    address public governance = address(1);
    address public management = address(2);
    address public treasury = address(3);
    address public guardian = address(4);
    address public user1 = address(5);
    address public user2 = address(6);
    address public user3 = address(7);
    address public user4 = address(8);
    address public user5 = address(9);
    address public longTermUser = address(0xAA);

    IWETH public constant WMNT =
        IWETH(address(0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8));

    address internal constant LENDING_POOL_ADDRESS_INIT =
        0x44949636f778fAD2b139E665aee11a2dc84A2976;

    address internal constant LENDLE_LENDING_POOL =
        0xCFa5aE7c2CE8Fadc6426C1ff872cA45378Fb7cF3;

    function setUp() internal {
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
        strategy1st.setLendingPool(LENDING_POOL_ADDRESS_INIT);
        strategy1st.updateUnlimitedSpending(true);
        strategy1st.updateUnlimitedSpendingInit(true);
        strategy1st.approveLendingPool();

        strategy2nd = new Strategy2nd(address(vault), governance); // Usa Strategy2nd
        strategy2nd.updateUnlimitedSpending(true); // Strategia approva Vault per 'want'

        vault.addStrategy(
            address(strategy1st),
            4_500, // 45% debtRatio
            0,
            type(uint256).max,
            0
        );
        vault.addStrategy(
            address(strategy2nd),
            4_500, // 45% debtRatio
            0, // minDebtPerHarvest
            type(uint256).max, // maxDebtPerHarvest
            0 // performanceFee
        );
        vault.setPerformanceFee(0);
        vault.setManagementFee(0);
        vault.setDepositLimit(type(uint256).max);
        vm.stopPrank();
        vm.deal(user1, 50000 ether);
        vm.deal(user2, 50000 ether);
        vm.deal(user3, 50000 ether);
        vm.deal(user4, 50000 ether);
        vm.deal(user5, 50000 ether);
        vm.deal(longTermUser, 5000 ether);
    }

    function wrapAndApprove(address user, uint256 amount) internal {
        vm.startPrank(user);
        WMNT.deposit{value: amount}();
        WMNT.approve(address(vault), amount);
        vm.stopPrank();
    }

    function depositToVault(
        address user,
        uint256 amount
    ) internal returns (uint256 shares) {
        vm.startPrank(user);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
        console.log(
            "User %a deposited %u WMNT, received %u shares.",
            user,
            amount,
            shares
        );
        console.log("PPS : u%", vault.pricePerShare());
    }

    function withdrawFromVault(
        address user,
        uint256 shares
    ) internal returns (uint256 assets) {
        vm.startPrank(user);
        uint256 userBalanceBefore = WMNT.balanceOf(user);

        // Aggiungi questi log per debug
        console.log("DEBUG: Attempting withdrawal for user %a.", user);
        console.log("DEBUG: User shares to withdraw: %u.", shares);
        console.log(
            "DEBUG: Vault totalAssets BEFORE withdrawal: %u.",
            vault.totalAssets()
        );
        console.log(
            "DEBUG: Vault WMNT balance (idle) BEFORE withdrawal: %u.",
            WMNT.balanceOf(address(vault))
        );
        console.log(
            "DEBUG: Vault totalDebt BEFORE withdrawal: %u.",
            vault.totalDebt()
        );

        assets = vault.withdraw(shares, user, 500); // maxLoss 0.01%
        vm.stopPrank();
        console.log(
            "Withdraw: User %a withdrew %u shares, received %u WMNT. PPS: %u",
            user,
            shares
        );
        console.log("Wmnt ", assets);
        console.log("PPS ", vault.pricePerShare());
        assertGe(
            WMNT.balanceOf(user),
            userBalanceBefore + assets - (assets / 1000),
            "User WMNT balance too low after withdrawal"
        );
    }

    function executeHarvest() internal {
        vm.startPrank(management);
        strategy1st.harvest();
        ILendingPoolInit(LENDING_POOL_ADDRESS_INIT).accrueInterest();
        strategy2nd.harvest();
        vm.stopPrank();
        console.log("Harvest executed. Current PPS: %u", vault.pricePerShare());
    }

    function executeSingleHarvest(address _strategy) internal {
        vm.startPrank(management);

        if (_strategy == address(strategy1st)) {
            strategy1st.harvest();
            ILendingPoolInit(LENDING_POOL_ADDRESS_INIT).accrueInterest();
        } else if (_strategy == address(strategy2nd)) {
            strategy2nd.harvest();
            vm.stopPrank();
        }
        console.log("Harvest executed. Current PPS: %u", vault.pricePerShare());
    }

    function signleUserDeposit() internal {
        setUp();
        vm.deal(user1, 5000 ether);
        wrapAndApprove(user1, 5000 ether);
        uint256 shares = depositToVault(user1, 1000 ether);
        assertEq(vault.balanceOf(user1), shares);
        executeHarvest();
        skip(80 days);
        executeHarvest();
        skip(10 hours);
        uint256 assets = withdrawFromVault(user1, shares);

        assertGe(assets, 1_000 ether, "Problem with interest");
    }

    function _logFullState(string memory stage) internal view {
        console.log("-----------------------------------------------------");
        console.log("LOG DI STATO: [%s]", stage);
        console.log("-----------------------------------------------------");

        // Stato del Vault
        console.log("VAULT STATE:");
        console.log("  - Total Assets (totale):  %s", vault.totalAssets());
        console.log("  - Total Debt (in strats): %s", vault.totalDebt());
        console.log(
            "  - Available (idle):       %s",
            WMNT.balanceOf(address(vault))
        );

        // Stato della Strategy1st
        if (address(strategy1st) != address(0)) {
            console.log("STRATEGY 1st (%s):", address(strategy1st));
            (
                ,
                ,
                uint256 debtRatio,
                ,
                ,
                ,
                uint256 totalDebt,
                ,
                
            ) = vault.strategies(address(strategy1st));
            console.log("  - Vault Debt Ratio:      %s / 10000", debtRatio);
            console.log("  - Vault Total Debt:      %s", totalDebt);
            console.log(
                "  - Strat Assets (est.):   %s",
                strategy1st.estimatedTotalAssets()
            );
        }

        // Stato della Strategy2nd
        if (address(strategy2nd) != address(0)) {
            console.log("STRATEGY 2nd (%s):", address(strategy2nd));
            (
                ,
                ,
                uint256 debtRatio2,
                ,
                ,
                ,
                ,
                ,
                
            ) = vault.strategies(address(strategy2nd));
            console.log("  - Vault Debt Ratio:      %s / 10000", debtRatio2);
            console.log("  - Vault Total Debt:      %s", debtRatio2);
            console.log(
                "  - Strat Assets (est.):   %s",
                strategy2nd.estimatedTotalAssets()
            );
        }
        console.log("-----------------------------------------------------\n");
    }
/*
    function testMultiUserLongTermActivity() public {
        setUp(); // Inizializza il Vault e le Strategie
        console.log("\n--- Starting Multi-User Long-Term Activity Test ---");

        // --- PREPARAZIONE INIZIALE (Depositi iniziali per tutti gli utenti) ---
        wrapAndApprove(user1, 1000 ether);
        depositToVault(user1, 500 ether);

        wrapAndApprove(user2, 1000 ether);
        depositToVault(user2, 700 ether);

        wrapAndApprove(user3, 1000 ether);
        depositToVault(user3, 300 ether);

        wrapAndApprove(user4, 1000 ether);
        depositToVault(user4, 900 ether);

        wrapAndApprove(user5, 1000 ether);
        depositToVault(user5, 450 ether);

        // Utente a lungo termine deposita una quantità specifica (per APY)
        wrapAndApprove(longTermUser, 1000 ether); // Approvazione per il deposito APY
        uint256 longTermDepositAmount = 100 ether;
        uint256 longTermShares = depositToVault(
            longTermUser,
            longTermDepositAmount
        );
        assertEq(
            vault.balanceOf(longTermUser),
            longTermShares,
            "Long-term user shares mismatch"
        );

        executeHarvest(); // Prima harvest dopo tutti i depositi iniziali

        // --- SIMULAZIONE TEMPORALE (2 ANNI) ---
        uint256 totalDays = 365 * 2; // 2 anni
        uint256 daysPassed = 0;
        uint256 harvestCounter = 0;

        // Array di utenti per interazioni dinamiche
        address[] memory activeUsers = new address[](5);
        activeUsers[0] = user1;
        activeUsers[1] = user2;
        activeUsers[2] = user3;
        activeUsers[3] = user4;
        activeUsers[4] = user5;

        // Variabili per tracciare le shares degli utenti, se necessario per prelievi precisi
        // mapping(address => uint256) userShares; // Non si può usare mapping in funzioni, solo come stato.
        // Dobbiamo ottenere il saldo attuale ogni volta.

        while (daysPassed < totalDays) {
            uint256 i = 0;
            uint256 daysToAdvance = 0;
            // Avanza il tempo in modo irregolare (tra 3 e 7 giorni)
            daysToAdvance = (block.timestamp % 5) + 2; // Simula un intervallo variabile
            if (daysPassed + daysToAdvance > totalDays) {
                daysToAdvance = totalDays - daysPassed;
            }
            vm.warp(block.timestamp + daysToAdvance * 1 days);
            daysPassed += daysToAdvance;

            // Esegui la harvest in modo irregolare (ogni 5-10 giorni reali, ma qui basato su loop)
            // Possiamo legare la harvest ad un intervallo o a una certa frequenza nel loop
            if (harvestCounter % 2 == 0) {
                // Harvest ogni 2 cicli (quindi ~6-14 giorni)
                executeHarvest();
            }
            harvestCounter++;

            // --- ATTIVITÀ UTENTE IRREGOLARE ---
            // Usa una logica più casuale per depositi/prelievi
            uint256 randomValue = uint256(
                keccak256(abi.encodePacked(block.timestamp, i))
            ); // Simula casualità

            address currentUser = activeUsers[randomValue % activeUsers.length]; // Scegli un utente a caso

            if (randomValue % 10 < 7) {
                // ~70% di probabilità di depositare
                uint256 depositAmount = (randomValue % 100 ether) + 1 ether; // Tra 1 e 100 ether
                wrapAndApprove(currentUser, depositAmount);
                depositToVault(currentUser, depositAmount);
            } else if (randomValue % 10 < 9) {
                // ~20% di probabilità di prelevare una parte
                uint256 userCurrentShares = vault.balanceOf(currentUser);
                if (userCurrentShares > 0) {
                    uint256 sharesToWithdraw = (userCurrentShares *
                        ((randomValue % 50) + 1)) / 100; // Tra 1% e 50%
                    if (sharesToWithdraw > 0) {
                        withdrawFromVault(currentUser, sharesToWithdraw);
                    }
                }
            } else {
                // ~10% di probabilità di prelevare tutto e ri-depositare
                uint256 userCurrentShares = vault.balanceOf(currentUser);
                if (userCurrentShares > 0) {
                    withdrawFromVault(currentUser, userCurrentShares);
                    wrapAndApprove(currentUser, 200 ether); // Rideposita una quantità fissa
                    depositToVault(currentUser, 200 ether);
                }
            }
            i++;
        }

        console.log("\n--- End of 2-Year Simulation Period ---");
        console.log("Final Vault TotalAssets: %u", vault.totalAssets());
        console.log("Final Vault PricePerShare: %u", vault.pricePerShare());

        // --- VERIFICA APY PER LONGTERMUSER ---
        console.log("\n--- Verifying APY for Long-Term User ---");
        uint256 withdrawnAssets = withdrawFromVault(
            longTermUser,
            longTermShares
        );
        console.log(
            "Long-Term User (Initial Deposit: %u WMNT, Final Withdraw: %u WMNT).",
            longTermDepositAmount,
            withdrawnAssets
        );

        uint256 profit = 0;
        if (withdrawnAssets > longTermDepositAmount) {
            profit = withdrawnAssets - longTermDepositAmount;
        }
        console.log("Long-Term User Profit: %u", profit);

        assertGe(
            profit,
            0,
            "Long-term user should have made a profit or at least broken even."
        );

        // Puoi impostare un APY minimo atteso in base ai tassi di interesse reali.
        // Ad esempio, se ti aspetti un APY minimo dell'1% annuo, in 2 anni sarebbe circa 2%.
        uint256 expectedMinProfit = (longTermDepositAmount * 2) / 100; // Esempio: 2% profitto sui 2 anni
        assertGe(
            profit,
            expectedMinProfit,
            "Long-term user profit is lower than expected minimum APY."
        );

        console.log("\n--- Multi-User Long-Term Activity Test Completed ---");
    }
*/
/*
    function testMigrationStrategy1to2() public {
        // --- 1. SETUP INIZIALE CON STRATEGY1ST ---
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
        strategy1st.setLendingPool(LENDING_POOL_ADDRESS_INIT);
        strategy1st.updateUnlimitedSpending(true);
        strategy1st.updateUnlimitedSpendingInit(true);
        strategy1st.approveLendingPool();
        strategy1st.setStrategist(management);

        vault.addStrategy(address(strategy1st), 9_000, 0, type(uint256).max, 0);
        vault.setPerformanceFee(0);
        vault.setManagementFee(0);
        vault.setDepositLimit(type(uint256).max);
        vm.stopPrank();
        // --- 2. DEPOSITO INIZIALE E ALLOCAZIONE ---
        vm.deal(user1, 50000 ether);
        wrapAndApprove(user1, 5000 ether);
        uint256 shares = depositToVault(user1, 1000 ether);
        assertEq(vault.balanceOf(user1), shares);

        executeSingleHarvest(address(strategy1st));

        _logFullState("Dopo il primo deposito e harvest in Strategy1st");

        // --- 3. ACCUMULO PROFITTI ---
        vm.startPrank(governance);
        ILendingPoolInit(LENDING_POOL_ADDRESS_INIT).accrueInterest();
        skip(20 days);
        ILendingPoolInit(LENDING_POOL_ADDRESS_INIT).accrueInterest();
        executeSingleHarvest(address(strategy1st));
        _logFullState("Dopo accumulo profitti in Strategy1st");
        skip(8 hours);
        vm.stopPrank();

        // --- 4. PREPARAZIONE ALLA MIGRAZIONE ---
        console.log(
            "\n\n>>>>>>>>>> INIZIO PROCESSO DI MIGRAZIONE <<<<<<<<<<\n"
        );
        vm.startPrank(governance);
        strategy2nd = new Strategy2nd(address(vault), governance);
        strategy2nd.setStrategist(management);
        vault.addStrategy(address(strategy2nd), 0, 0, type(uint256).max, 0);

        vault.updateStrategyDebtRatio(address(strategy1st), 0);
        vault.updateStrategyDebtRatio(address(strategy2nd), 9_000);
        vm.stopPrank();
        _logFullState("Debt Ratio aggiornati per la migrazione");

        // --- 5. ESECUZIONE MIGRAZIONE ---

        // PASSO 1: Rimuovi i fondi dalla vecchia strategia
        executeSingleHarvest(address(strategy1st));
        skip(1 hours);

        _logFullState(
            "Dopo harvest su Strategy1st (fondi restituiti al vault)"
        );

        (, , , , , , uint256 totalDebt, , ) = vault.strategies(
            address(strategy1st)
        );

        assertApproxEqAbs(
            totalDebt,
            0,
            100,
            "Debt di Strategy1st dovrebbe essere 0"
        );

        // PASSO 2: Alloca i fondi alla nuova strategia
        executeSingleHarvest(address(strategy2nd));
        _logFullState(
            "Dopo harvest su Strategy2nd (fondi allocati alla nuova)"
        );

        (, , , , , , uint256 totalDebt2, , ) = vault.strategies(
            address(strategy2nd)
        );

        assertTrue(
            totalDebt2 > 0,
            "Strategy2nd dovrebbe avere debito ora"
        );

        console.log(
            "\n>>>>>>>>>> MIGRAZIONE COMPLETATA CON SUCCESSO <<<<<<<<<<\n"
        );

        // --- 6. CONTINUA OPERATIVITÀ CON LA NUOVA STRATEGIA ---
        skip(20 days);
        executeSingleHarvest(address(strategy2nd));
        skip(10 hours);
        _logFullState("Dopo un periodo di attivita con Strategy2nd");
        
    }
*/


     function testMigrationStrategy2to1() public {
        // --- 1. SETUP INIZIALE CON STRATEGY1ST ---
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
        strategy2nd.setStrategist(management);


        vault.addStrategy(address(strategy2nd), 9_000, 0, type(uint256).max, 0);
        vault.setPerformanceFee(0);
        vault.setManagementFee(0);
        vault.setDepositLimit(type(uint256).max);
        vm.stopPrank();
        // --- 2. DEPOSITO INIZIALE E ALLOCAZIONE ---
        vm.deal(user1, 50000 ether);
        wrapAndApprove(user1, 5000 ether);
        uint256 shares = depositToVault(user1, 1000 ether);
        assertEq(vault.balanceOf(user1), shares);

        executeSingleHarvest(address(strategy2nd));

        _logFullState("Dopo il primo deposito e harvest in Strategy1st");

        // --- 3. ACCUMULO PROFITTI ---
        skip(20 days);
        executeSingleHarvest(address(strategy2nd));
        _logFullState("Dopo accumulo profitti in Strategy1st");
        skip(8 hours);

        // --- 4. PREPARAZIONE ALLA MIGRAZIONE ---
        console.log(
            "\n\n>>>>>>>>>> INIZIO PROCESSO DI MIGRAZIONE <<<<<<<<<<\n"
        );
        vm.startPrank(governance);

        strategy1st = new Strategy1st(address(vault), governance);
        strategy1st.setLendingPool(LENDING_POOL_ADDRESS_INIT);
        strategy1st.updateUnlimitedSpending(true);
        strategy1st.updateUnlimitedSpendingInit(true);
        strategy1st.approveLendingPool();
        strategy1st.setStrategist(management);



      
        vault.addStrategy(address(strategy1st), 0, 0, type(uint256).max, 0);

        vault.updateStrategyDebtRatio(address(strategy2nd), 0);
        vault.updateStrategyDebtRatio(address(strategy1st), 9_000);
        vm.stopPrank();
        _logFullState("Debt Ratio aggiornati per la migrazione");

        // --- 5. ESECUZIONE MIGRAZIONE ---

        // PASSO 1: Rimuovi i fondi dalla vecchia strategia
        executeSingleHarvest(address(strategy2nd));

        skip(1 hours);

        _logFullState(
            "Dopo harvest su Strategy1st (fondi restituiti al vault)"
        );

        (, , , , , , uint256 totalDebt, , ) = vault.strategies(
            address(strategy2nd)
        );

        assertApproxEqAbs(
            totalDebt,
            0,
            100,
            "Debt di Strategy1st dovrebbe essere 0"
        );

        // PASSO 2: Alloca i fondi alla nuova strategia
        executeSingleHarvest(address(strategy1st));
        ILendingPoolInit(LENDING_POOL_ADDRESS_INIT).accrueInterest();

        _logFullState(
            "Dopo harvest su Strategy2nd (fondi allocati alla nuova)"
        );

        (, , , , , , uint256 totalDebt2, , ) = vault.strategies(
            address(strategy1st)
        );

        assertTrue(
            totalDebt2 > 0,
            "Strategy2nd dovrebbe avere debito ora"
        );

        console.log(
            "\n>>>>>>>>>> MIGRAZIONE COMPLETATA CON SUCCESSO <<<<<<<<<<\n"
        );

        // --- 6. CONTINUA OPERATIVITÀ CON LA NUOVA STRATEGIA ---
        skip(20 days);
        executeSingleHarvest(address(strategy1st));
        ILendingPoolInit(LENDING_POOL_ADDRESS_INIT).accrueInterest();
        
        skip(10 hours);
        _logFullState("Dopo un periodo di attivita con Strategy2nd");
/*
        */
    }
}
