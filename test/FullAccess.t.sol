// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DoppioTest} from "./DoppioTest.t.sol";

/**
 *@title AccessControlTest
 *@notice Test suite dedicated to verifying access controls (role permissions) for the Vault and Strategies.
 *@dev Inherits from DoppioTest to reuse addresses and the setup function.
 */

contract AccessControlTest is DoppioTest {
    // =================================================================
    //                    TEST DI ACCESSO SUL VAULT
    // =================================================================

    address public newGovernance = makeAddr("newGovernance");
    address public newManagement = makeAddr("newManagement");
    address public newGuardian = makeAddr("newGuardian");
    address public newStrategist = makeAddr("newStrategist");
    address public newKeeper = makeAddr("newKeeper");

    function testVault_GovernanceFunctions() public {
        setUpWithFee();
        address unauthorizedUser = user1;

        // --- setPerformanceFee ---
        vm.startPrank(unauthorizedUser);
        vm.expectRevert("Vault: !governance");
        vault.setPerformanceFee(200);
        vm.stopPrank();

        vm.startPrank(governance);
        vault.setPerformanceFee(200);
        assertEq(vault.performanceFee(), 200);
        vm.stopPrank();

        // --- addStrategy ---
        vm.startPrank(unauthorizedUser);
        vm.expectRevert("Vault: !governance");
        vault.addStrategy(address(0xdead), 1000, 0, 0, 0);
        vm.stopPrank();

        // --- setDepositLimit ---
        vm.startPrank(unauthorizedUser);
        vm.expectRevert("Vault: !governance");
        vault.setDepositLimit(12345);
        vm.stopPrank();
    }

    function testVault_ManagementFunctions() public {
        setUpWithFee();
        address unauthorizedUser = user1;
        // --- updateStrategyDebtRatio ---

        vm.startPrank(unauthorizedUser);
        vm.expectRevert("Vault: !authorized");
        vault.updateStrategyDebtRatio(address(strategy1st), 5000);
        vm.stopPrank();

        vm.startPrank(management);
        vault.updateStrategyDebtRatio(address(strategy1st), 5000);
        vm.stopPrank();

        vm.startPrank(governance);
        vault.updateStrategyDebtRatio(address(strategy1st), 3000);
        vm.stopPrank();
    }

    function testVault_GuardianFunctions() public {
        setUpWithFee();
        address unauthorizedUser = user1;

        // --- setEmergencyShutdown(true) ---

        // Test fallimento da utente non autorizzato
        vm.startPrank(unauthorizedUser);
        vm.expectRevert("Vault: !guardian or !governance");
        vault.setEmergencyShutdown(true);
        vm.stopPrank();

        // Test successo da guardian
        vm.startPrank(guardian);
        vault.setEmergencyShutdown(true);
        assertTrue(vault.emergencyShutdown());
        vm.stopPrank();

        // Reset per il prossimo test (solo la governance può disattivarlo)
        vm.startPrank(governance);
        vault.setEmergencyShutdown(false);
        vm.stopPrank();
    }

    // =================================================================
    //                   TEST DI ACCESSO SULLE STRATEGIE
    // =================================================================

    function testStrategies_OwnerFunctions() public {
        setUpWithFee();
        address unauthorizedUser = user1;

        // --- Funzioni di Strategy1st ---
        vm.startPrank(unauthorizedUser);
        vm.expectRevert();
        strategy1st.setLendingPool(address(0xdead));

        vm.expectRevert();
        strategy1st.updateUnlimitedSpending(false);
        vm.stopPrank();

        // --- Funzioni di Strategy2nd ---
        vm.startPrank(unauthorizedUser);
        vm.expectRevert();
        strategy2nd.setlToken(address(0xdead));

        vm.expectRevert();
        strategy2nd.updateUnlimitedSpendingLendl(false);
        vm.stopPrank();
    }

    function testStrategies_KeeperFunctions() public {
        setUpWithFee();
        address unauthorizedUser = user1;
        // La BaseStrategy usa `_onlyKeepers` che include strategist e governance

        // --- Harvest ---
        vm.startPrank(unauthorizedUser);
        vm.expectRevert();
        strategy1st.harvest();

        vm.expectRevert();
        strategy2nd.harvest();
        vm.stopPrank();

        // Test successo da management (che abbiamo impostato come strategist/keeper)
        vm.startPrank(management);
        strategy1st.harvest();
        strategy2nd.harvest();
        vm.stopPrank();
    }

    function testRoleManagementLifecycle() public {
        setUpWithFee();

        console.log("\n--- Inizio Test Ciclo di Vita Gestione Ruoli ---");

        // =================================================================
        //                 1. TEST TRASFERIMENTO GOVERNANCE DEL VAULT
        // =================================================================
        console.log("\n[1] Test trasferimento Governance del Vault...");

        vm.startPrank(governance);
        vault.setGovernance(newGovernance);
        assertEq(
            vault.pendingGovernance(),
            newGovernance,
            "pendingGovernance impostato correttamente"
        );
        vm.stopPrank();

        vm.startPrank(newGovernance);
        vault.acceptGovernance();
        assertEq(
            vault.governance(),
            newGovernance,
            "La nuova governance e'stata impostata correttamente"
        );
        vm.stopPrank();

        vm.startPrank(governance);
        vm.expectRevert("Vault: !governance");
        vault.setDepositLimit(1 ether);
        vm.stopPrank();
        console.log("--> Trasferimento Governance OK.");

        // =================================================================
        //                 2. TEST ASSEGNAZIONE NUOVI RUOLI NEL VAULT
        // =================================================================
        console.log("\n[2] Test assegnazione ruoli Management e Guardian...");

        vm.startPrank(newGovernance);

        vault.setManagement(newManagement);
        assertEq(
            vault.management(),
            newManagement,
            "newManagement non impostato"
        );

        vault.setGuardian(newGuardian);
        assertEq(vault.guardian(), newGuardian, "newGuardian  impostato");

        vm.stopPrank();

        vm.startPrank(management);
        vm.expectRevert("Vault: !authorized");
        vault.updateStrategyDebtRatio(address(strategy1st), 5000);
        vm.stopPrank();
        console.log("--> Assegnazione ruoli Vault OK.");

        // =================================================================
        //                 3. TEST ASSEGNAZIONE RUOLI DELLA STRATEGIA
        // =================================================================
        console.log(
            "\n[3] Test assegnazione ruoli Strategist e Keeper (su Strategy1st)..."
        );

        vm.startPrank(newGovernance);

        strategy1st.setStrategist(newStrategist);
        assertEq(
            strategy1st.strategist(),
            newStrategist,
            "newStrategist non impostato"
        );
        vm.stopPrank();

        vm.startPrank(newStrategist);
        strategy1st.setKeeper(newKeeper);
        assertEq(strategy1st.keeper(), newKeeper, "newKeeper non impostato");
        vm.stopPrank();

        vm.startPrank(management);
        vm.expectRevert();
        strategy1st.harvest();
        vm.stopPrank();

        vm.startPrank(newKeeper);
        strategy1st.harvest();
        vm.stopPrank();
        console.log("--> Assegnazione ruoli Strategia OK.");

        console.log(
            "\n--- Test Ciclo di Vita Gestione Ruoli Completato con Successo ---"
        );
    }
}
