// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StMNT} from "../contracts/Vault.sol";
import {Strategy1st} from "../contracts/Strategy1st.sol";
import {Strategy2nd} from "../contracts/Strategy2nd.sol";
import {MockERC20} from "../contracts/mockWMNT.sol";
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
    address public boosterUser = address(0xD);

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

        strategy2nd = new Strategy2nd(address(vault), governance);
        strategy2nd.updateUnlimitedSpending(true);

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

    function setUpWithFee() internal {
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

        strategy2nd = new Strategy2nd(address(vault), governance);
        strategy2nd.updateUnlimitedSpending(true);

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
        vault.setPerformanceFee(100); // performance fee 1%
        vault.setManagementFee(100); // managment fee 1%
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

        console.log("VAULT STATE:");
        console.log("  - Total Assets (totale):  %s", vault.totalAssets());
        console.log("  - Total Debt (in strats): %s", vault.totalDebt());
        console.log(
            "  - Available (idle):       %s",
            WMNT.balanceOf(address(vault))
        );

        if (address(strategy1st) != address(0)) {
            console.log("STRATEGY 1st (%s):", address(strategy1st));
            (, , uint256 debtRatio, , , , uint256 totalDebt, , ) = vault
                .strategies(address(strategy1st));
            console.log("  - Vault Debt Ratio:      %s / 10000", debtRatio);
            console.log("  - Vault Total Debt:      %s", totalDebt);
            console.log(
                "  - Strat Assets (est.):   %s",
                strategy1st.estimatedTotalAssets()
            );
        }

        if (address(strategy2nd) != address(0)) {
            console.log("STRATEGY 2nd (%s):", address(strategy2nd));
            (, , uint256 debtRatio2, , , , , , ) = vault.strategies(
                address(strategy2nd)
            );
            console.log("  - Vault Debt Ratio:      %s / 10000", debtRatio2);
            console.log("  - Vault Total Debt:      %s", debtRatio2);
            console.log(
                "  - Strat Assets (est.):   %s",
                strategy2nd.estimatedTotalAssets()
            );
        }
        console.log("-----------------------------------------------------\n");
    }

    function testMultiUserLongTermActivity() public {
        setUp();
        console.log("\n--- Starting Multi-User Long-Term Activity Test ---");

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

        wrapAndApprove(longTermUser, 1000 ether);
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

        executeHarvest();

        // --- SIMULAZIONE TEMPORALE (2 ANNI) ---
        uint256 totalDays = 365 * 2; // 2 anni
        uint256 daysPassed = 0;
        uint256 harvestCounter = 0;

        address[] memory activeUsers = new address[](5);
        activeUsers[0] = user1;
        activeUsers[1] = user2;
        activeUsers[2] = user3;
        activeUsers[3] = user4;
        activeUsers[4] = user5;

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

            if (harvestCounter % 2 == 0) {
                executeHarvest();
            }
            harvestCounter++;

            uint256 randomValue = uint256(
                keccak256(abi.encodePacked(block.timestamp, i))
            ); // Simula casualità

            address currentUser = activeUsers[randomValue % activeUsers.length]; // Scegli un utente a caso

            if (randomValue % 10 < 7) {
                // ~70% di probabilità di depositare
                uint256 depositAmount = (randomValue % 100 ether) + 1 ether;
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

        uint256 expectedMinProfit = (longTermDepositAmount * 2) / 100; // Esempio: 2%
        assertGe(
            profit,
            expectedMinProfit,
            "Long-term user profit is lower than expected minimum APY."
        );

        console.log("\n--- Multi-User Long-Term Activity Test Completed ---");
    }

    function testMigrationStrategy1to2() public {
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

        assertTrue(totalDebt2 > 0, "Strategy2nd dovrebbe avere debito ora");

        console.log(
            "\n>>>>>>>>>> MIGRAZIONE COMPLETATA CON SUCCESSO <<<<<<<<<<\n"
        );

        // --- 6. CONTINUA OPERATIVITÀ CON LA NUOVA STRATEGIA ---
        skip(20 days);
        executeSingleHarvest(address(strategy2nd));
        skip(10 hours);
        _logFullState("Dopo un periodo di attivita con Strategy2nd");
    }

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

        assertTrue(totalDebt2 > 0, "Strategy2nd dovrebbe avere debito ora");

        console.log(
            "\n>>>>>>>>>> MIGRAZIONE COMPLETATA CON SUCCESSO <<<<<<<<<<\n"
        );

        // --- 6. CONTINUA OPERATIVITÀ CON LA NUOVA STRATEGIA ---
        skip(20 days);
        executeSingleHarvest(address(strategy1st));
        ILendingPoolInit(LENDING_POOL_ADDRESS_INIT).accrueInterest();

        skip(10 hours);
        _logFullState("Dopo un periodo di attivita con Strategy2nd");
    }

    function testMultiUserLongTermActivityWithFee() public {
        setUpWithFee();
        console.log(
            "\n--- Starting Multi-User Long-Term Activity Test with Fees ---"
        );

        // --- PREPARAZIONE INIZIALE ---
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

        executeHarvest();

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

            if (harvestCounter % 2 == 0) {
                executeHarvest();
            }
            harvestCounter++;

            // --- ATTIVITÀ UTENTE IRREGOLARE ---
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

        uint256 expectedMinProfit = (longTermDepositAmount * 1) / 100; // Esempio: 2% profitto sui 2 anni
        assertGe(
            profit,
            expectedMinProfit,
            "Long-term user profit is lower than expected minimum APY."
        );

        console.log("\n--- Multi-User Long-Term Activity Test Completed ---");
    }

    function testFeeGenerationAndCollection() public {
        setUpWithFee();

        address rewardsRecipient = treasury;

        console.log("\n--- Starting Fee Generation & Collection Test ---");
        console.log("Performance Fee (BPS): %s", vault.performanceFee());
        console.log("Management Fee (BPS): %s", vault.managementFee());
        console.log("Rewards Recipient Address: %s", rewardsRecipient);

        uint256 initialRewardsShares = vault.balanceOf(rewardsRecipient);
        assertEq(initialRewardsShares, 0, "Initial rewards shares should be 0");

        // --- SIMULAZIONE ATTIVITÀ UTENTI PER GENERARE PROFITTI E COMMISSIONI ---

        wrapAndApprove(user1, 1000 ether);
        depositToVault(user1, 500 ether);

        wrapAndApprove(user2, 1000 ether);
        depositToVault(user2, 700 ether);

        // Eseguiamo una serie di cicli di tempo e harvest per accumulare commissioni
        for (uint i = 0; i < 10; i++) {
            vm.warp(block.timestamp + 30 days);
            executeHarvest();
        }

        console.log("\n--- End of Simulation Period ---");
        _logFullState("Stato finale dopo la simulazione");

        // --- VERIFICA DELLA RACCOLTA DELLE COMMISSIONI ---
        console.log("\n--- Verifying Fee Collection ---");

        uint256 finalRewardsShares = vault.balanceOf(rewardsRecipient);
        console.log(
            "Vault shares collected by rewards address: %u",
            finalRewardsShares
        );

        assertTrue(
            finalRewardsShares > initialRewardsShares,
            "Rewards address should have collected vault shares"
        );

        // 2. Verifichiamo che le quote raccolte abbiano un valore reale
        console.log(
            "Rewards recipient is now withdrawing collected fee shares..."
        );

        vm.deal(rewardsRecipient, 1 ether);
        vm.startPrank(rewardsRecipient);
        uint256 withdrawnFeesInWMNT = vault.withdraw(
            finalRewardsShares,
            rewardsRecipient,
            100
        ); // Max loss 1%
        vm.stopPrank();

        console.log(
            "Amount of WMNT collected by redeeming fee shares: %u",
            withdrawnFeesInWMNT
        );

        assertTrue(
            withdrawnFeesInWMNT > 0,
            "Withdrawn fees in WMNT should be greater than 0"
        );

        console.log(
            "\n--- Fee Generation & Collection Test Completed Successfully ---"
        );
    }

    function testSweepFunction() public {
        MockERC20 testToken = new MockERC20("mock Sweep", "swe");
        testToken.mint(address(this), 1000 ether);

        setUpWithFee();
        testToken.transfer(address(vault), 1000 ether);

        assertEq(
            testToken.balanceOf(address(governance)),
            0,
            "governace have already sweep tokens"
        );

        vm.prank(user1);
        vm.expectRevert("Vault: !governance");
        vault.sweep(address(testToken), 1000 ether);

        vm.prank(governance);
        vault.sweep(address(testToken), 1000 ether);

        assertEq(
            testToken.balanceOf(address(governance)),
            1000 ether,
            "governace can't withdraw sweep tokens"
        );

        vm.deal(user1, 50000 ether);
        wrapAndApprove(user1, 1000 ether);
        depositToVault(user1, 100 ether);

        vm.prank(governance);
        vm.expectRevert("Vault: no excess vault token");
        vault.sweep(address(WMNT), 100 ether);

        vm.prank(user1);
        WMNT.transfer(address(vault), 10 ether);

        vm.prank(governance);
        vault.sweep(address(WMNT), 10 ether);
    }

    function testFeeGenerationAndCollectionWithBoost1stStrategy() public {
        setUpWithFee();

        address rewardsRecipient = treasury;

        console.log("\n--- Starting Fee Generation & Collection Test ---");
        console.log("Performance Fee (BPS): %s", vault.performanceFee());
        console.log("Management Fee (BPS): %s", vault.managementFee());
        console.log("Rewards Recipient Address: %s", rewardsRecipient);

        uint256 initialRewardsShares = vault.balanceOf(rewardsRecipient);
        assertEq(initialRewardsShares, 0, "Initial rewards shares should be 0");

        // --- SIMULAZIONE ATTIVITÀ UTENTI PER GENERARE PROFITTI E COMMISSIONI ---

        wrapAndApprove(user1, 1000 ether);
        depositToVault(user1, 500 ether);

        wrapAndApprove(user2, 1000 ether);
        depositToVault(user2, 700 ether);

        vm.warp(block.timestamp + 30 days);
        executeHarvest();

        wrapAndApprove(user5, 100 ether);
        vm.prank(user5);
        WMNT.transfer(address(strategy1st), 100 ether);
        console.log("Aggiungiamo 100 ether per boost");

        vm.warp(block.timestamp + 30 days);
        executeHarvest();

        console.log("\n--- End of Simulation Period ---");
        _logFullState("Stato finale dopo la simulazione");

        // --- VERIFICA DELLA RACCOLTA DELLE COMMISSIONI ---
        console.log("\n--- Verifying Fee Collection ---");

        uint256 finalRewardsShares = vault.balanceOf(rewardsRecipient);
        console.log(
            "Vault shares collected by rewards address: %u",
            finalRewardsShares
        );

        assertTrue(
            finalRewardsShares > initialRewardsShares,
            "Rewards address should have collected vault shares"
        );

        // 2. Verifichiamo che le quote raccolte abbiano un valore reale

        console.log(
            "Rewards recipient is now withdrawing collected fee shares..."
        );

        vm.deal(rewardsRecipient, 1 ether);
        vm.startPrank(rewardsRecipient);
        uint256 withdrawnFeesInWMNT = vault.withdraw(
            finalRewardsShares,
            rewardsRecipient,
            100
        ); // Max loss 1%
        vm.stopPrank();

        console.log(
            "Amount of WMNT collected by redeeming fee shares: %u",
            withdrawnFeesInWMNT
        );

        assertTrue(
            withdrawnFeesInWMNT > 0,
            "Withdrawn fees in WMNT should be greater than 0"
        );

        console.log(
            "\n--- Fee Generation & Collection Test Completed Successfully ---"
        );
    }

    function testFeeGenerationAndCollectionWithBoost2ndStrategy() public {
        setUpWithFee();

        address rewardsRecipient = treasury;

        console.log("\n--- Starting Fee Generation & Collection Test ---");
        console.log("Performance Fee (BPS): %s", vault.performanceFee());
        console.log("Management Fee (BPS): %s", vault.managementFee());
        console.log("Rewards Recipient Address: %s", rewardsRecipient);

        uint256 initialRewardsShares = vault.balanceOf(rewardsRecipient);
        assertEq(initialRewardsShares, 0, "Initial rewards shares should be 0");

        // --- SIMULAZIONE ATTIVITÀ UTENTI PER GENERARE PROFITTI E COMMISSIONI ---

        wrapAndApprove(user1, 1000 ether);
        depositToVault(user1, 500 ether);

        wrapAndApprove(user2, 1000 ether);
        depositToVault(user2, 700 ether);

        vm.warp(block.timestamp + 30 days);
        executeHarvest();

        wrapAndApprove(user5, 100 ether);
        vm.prank(user5);
        WMNT.transfer(address(strategy2nd), 100 ether);
        console.log("Aggiungiamo 100 ether per boost");

        vm.warp(block.timestamp + 30 days);
        executeHarvest();

        console.log("\n--- End of Simulation Period ---");
        _logFullState("Stato finale dopo la simulazione");

        // --- VERIFICA DELLA RACCOLTA DELLE COMMISSIONI ---
        console.log("\n--- Verifying Fee Collection ---");

        uint256 finalRewardsShares = vault.balanceOf(rewardsRecipient);
        console.log(
            "Vault shares collected by rewards address: %u",
            finalRewardsShares
        );

        assertTrue(
            finalRewardsShares > initialRewardsShares,
            "Rewards address should have collected vault shares"
        );

        // 2. Verifichiamo che le quote raccolte abbiano un valore reale
        console.log(
            "Rewards recipient is now withdrawing collected fee shares..."
        );

        vm.deal(rewardsRecipient, 1 ether);
        vm.startPrank(rewardsRecipient);
        uint256 withdrawnFeesInWMNT = vault.withdraw(
            finalRewardsShares,
            rewardsRecipient,
            100
        ); // Max loss 1%
        vm.stopPrank();

        console.log(
            "Amount of WMNT collected by redeeming fee shares: %u",
            withdrawnFeesInWMNT
        );

        assertTrue(
            withdrawnFeesInWMNT > 0,
            "Withdrawn fees in WMNT should be greater than 0"
        );

        console.log(
            "\n--- Fee Generation & Collection Test Completed Successfully ---"
        );
    }

    function testStressTestWithFeesAndBoosts() public {
        setUpWithFee();
        console.log(
            "\n--- Starting Long-Term Stress Test with Fees & Random Boosts ---"
        );

        // --- PREPARAZIONE UTENTI ---
        wrapAndApprove(user1, 1000 ether);
        depositToVault(user1, 500 ether);
        wrapAndApprove(user2, 1000 ether);
        depositToVault(user2, 700 ether);
        wrapAndApprove(user3, 1000 ether);
        depositToVault(user3, 300 ether);

        // Utente per il controllo APY
        wrapAndApprove(longTermUser, 1000 ether);
        uint256 longTermDepositAmount = 100 ether;
        uint256 longTermShares = depositToVault(
            longTermUser,
            longTermDepositAmount
        );

        // Utente "Booster" che donerà fondi
        vm.deal(boosterUser, 10000 ether);
        vm.startPrank(boosterUser);
        WMNT.deposit{value: 10000 ether}();
        vm.stopPrank();

        executeHarvest();

        // --- SIMULAZIONE TEMPORALE (2 ANNI) ---
        uint256 totalDays = 365 * 2;
        uint256 daysPassed = 0;
        uint256 harvestCounter = 0;

        address[] memory activeUsers = new address[](3);
        activeUsers[0] = user1;
        activeUsers[1] = user2;
        activeUsers[2] = user3;

        address[] memory activeStrategies = new address[](2);
        activeStrategies[0] = address(strategy1st);
        activeStrategies[1] = address(strategy2nd);

        while (daysPassed < totalDays) {
            // --- AVANZAMENTO TEMPORALE ---
            uint256 daysToAdvance = (block.timestamp % 5) + 3; // Avanza da 3 a 7 giorni
            if (daysPassed + daysToAdvance > totalDays) {
                daysToAdvance = totalDays - daysPassed;
            }
            vm.warp(block.timestamp + daysToAdvance * 1 days);
            daysPassed += daysToAdvance;

            // --- LOGICA DI HARVEST E BOOST ---
            uint256 randomValue = uint256(
                keccak256(abi.encodePacked(block.timestamp, daysPassed))
            );
            bool boostedThisCycle = false;

            // 1. Controlla prima se avviene un boost
            if (randomValue % 100 < 20) {
                // 20% di probabilità
                uint256 boostAmount = (randomValue % 96 ether) + 5 ether; // Boost tra 5 e 100 ether
                address targetStrategy = activeStrategies[
                    randomValue % activeStrategies.length
                ];

                console.log("\n!!! BOOSTING EVENT !!!");
                console.log(
                    "Boosting strategy %s with %u WMNT",
                    targetStrategy,
                    boostAmount
                );

                vm.startPrank(boosterUser);
                WMNT.transfer(targetStrategy, boostAmount);
                vm.stopPrank();

                executeHarvest();
                console.log("Boost harvest completed.");
                boostedThisCycle = true;
            }

            // 2. Esegui l'harvest periodico SOLO SE non c'è stato un boost in questo ciclo
            if (!boostedThisCycle && (harvestCounter % 2 == 0)) {
                executeHarvest();
            }
            harvestCounter++;

            // --- ATTIVITÀ UTENTE CASUALE ---
            address currentUser = activeUsers[randomValue % activeUsers.length];
            if (randomValue % 10 < 6) {
                // 60% prob. di depositare
                uint256 depositAmount = (randomValue % 50 ether) + 1 ether;
                wrapAndApprove(currentUser, depositAmount);
                depositToVault(currentUser, depositAmount);
            } else {
                // 40% prob. di prelevare una parte
                uint256 userShares = vault.balanceOf(currentUser);
                if (userShares > 1 ether) {
                    uint256 sharesToWithdraw = (userShares *
                        (randomValue % 40)) / 100; // Preleva fino al 40%
                    withdrawFromVault(currentUser, sharesToWithdraw);
                }
            }
        }

        console.log("\n--- Fine della Simulazione di 2 Anni ---");
        _logFullState("State after the stress test");

        // --- VERIFICA FINALE APY PER L'UTENTE A LUNGO TERMINE ---
        console.log("\n--- Verifica APY per l'Utente a Lungo Termine ---");
        uint256 withdrawnAssets = withdrawFromVault(
            longTermUser,
            longTermShares
        );
        console.log(
            "Utente a Lungo Termine (Deposito Iniziale: %u WMNT, Prelievo Finale: %u WMNT).",
            longTermDepositAmount,
            withdrawnAssets
        );

        uint256 profit = 0;
        if (withdrawnAssets > longTermDepositAmount) {
            profit = withdrawnAssets - longTermDepositAmount;
        }
        console.log("Profitto Utente a Lungo Termine: %u", profit);

        assertGe(
            profit,
            0,
            "L'utente a lungo termine non dovrebbe aver perso capitale."
        );

        assertTrue(
            vault.balanceOf(treasury) > 0,
            "Il treasury dovrebbe aver raccolto commissioni."
        );

        console.log("\n--- Stress Test Completato con Successo ---");
    }

    function testFullAccessControl() public {
        setUpWithFee();

        assertEq(vault.governance(), governance);
        assertEq(vault.management(), management);
        assertEq(vault.guardian(), guardian);
        assertEq(vault.rewards(), treasury);
        assertEq(vault.name(), "stMNT");
        assertEq(vault.symbol(), "stMNT");
        assertEq(address(vault.token()), address(WMNT));
        assertEq(vault.performanceFee(), 100);
        assertEq(vault.managementFee(), 100);
        assertEq(vault.lockedProfitDegradation(), 46000000000000);
        assertEq(vault.depositLimit(), type(uint256).max);

        vm.stopPrank();
        vm.startPrank(user1);
        vm.expectRevert("Vault: !governance");
        vault.setPerformanceFee(1000);
        vm.expectRevert("Vault: !governance");
        vault.setManagementFee(1000);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert();
        strategy1st.setLendingPool(LENDING_POOL_ADDRESS_INIT);

        vm.expectRevert();
        strategy1st.updateUnlimitedSpending(true);

        vm.expectRevert();
        strategy1st.updateUnlimitedSpendingInit(true);

        vm.expectRevert();
        strategy1st.approveLendingPool();

        vm.expectRevert();
        strategy2nd.updateUnlimitedSpending(true);

        vm.expectRevert("Vault: !governance");
        vault.addStrategy(
            address(strategy1st),
            4_500, // 45% debtRatio
            0,
            type(uint256).max,
            0
        );

        vm.expectRevert("Vault: !governance");
        vault.addStrategy(
            address(strategy2nd),
            4_500, // 45% debtRatio
            0, // minDebtPerHarvest
            type(uint256).max, // maxDebtPerHarvest
            0 // performanceFee
        );

        vm.expectRevert("Vault: !governance");
        vault.setPerformanceFee(100); // performance fee 1%

        vm.expectRevert("Vault: !governance");
        vault.setManagementFee(100); // managment fee 1%

        vm.expectRevert("Vault: !governance");
        vault.setDepositLimit(type(uint256).max);

        vm.expectRevert();
        strategy1st.harvest();

        vm.expectRevert();
        strategy2nd.harvest();

        vm.stopPrank();
    }
}
