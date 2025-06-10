// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DoppioTest} from "./DoppioTest.t.sol"; // Importa il tuo test esistente per usare il suo setup

/**
 * @title AccessControlTest
 * @notice Test suite dedicata a verificare i controlli degli accessi (role permissions)
 * per il Vault e le Strategie.
 * @dev Eredita da DoppioTest per riutilizzare gli indirizzi e la funzione di setup.
 */
contract AccessControlTest is DoppioTest {
    // La funzione setUp() viene ereditata da DoppioTest, quindi vault, strategie, etc.
    // sono già inizializzati prima di ogni test qui sotto.

    // =================================================================
    //                    TEST DI ACCESSO SUL VAULT
    // =================================================================

    function testVault_GovernanceFunctions() public {
        setUpWithFee(); // Assicura che tutto sia deployato
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

        // --- Altre funzioni di governance da testare ---
        // setManagement, setRewards, setEmergencyShutdown(false), etc.
        // ... (aggiungere test per ogni funzione `onlyGovernance`)
    }

    function testVault_ManagementFunctions() public {
        setUpWithFee();
        address unauthorizedUser = user1;
        // --- updateStrategyDebtRatio ---
        // Questa funzione può essere chiamata sia da management che da governance
        
        // Test fallimento da utente non autorizzato
        vm.startPrank(unauthorizedUser);
        vm.expectRevert("Vault: !authorized");
        vault.updateStrategyDebtRatio(address(strategy1st), 5000);
        vm.stopPrank();

        // Test successo da management
        vm.startPrank(management);
        vault.updateStrategyDebtRatio(address(strategy1st), 5000);
        //assertEq(vault.strategies(address(strategy1st)).debtRatio, 5000);
        vm.stopPrank();

        // Test successo da governance
        vm.startPrank(governance);
        vault.updateStrategyDebtRatio(address(strategy1st), 3000);
        //assertEq(vault.strategies(address(strategy1st)).debtRatio, 6000);
        vm.stopPrank();
       
    }

    function testVault_GuardianFunctions() public {
        setUpWithFee();
        address unauthorizedUser = user1;

        // --- setEmergencyShutdown(true) ---
        // Può essere chiamato da guardian o governance

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
        vm.expectRevert(abi.encodeWithSignature(
         "OwnableUnauthorizedAccount(address)",
                address(unauthorizedUser)
        ));
        strategy1st.setLendingPool(address(0xdead));
        
           vm.expectRevert(abi.encodeWithSignature(
         "OwnableUnauthorizedAccount(address)",
                address(unauthorizedUser)
        ));
        strategy1st.updateUnlimitedSpending(false);
        vm.stopPrank();
        
        // --- Funzioni di Strategy2nd ---
        vm.startPrank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSignature(
         "OwnableUnauthorizedAccount(address)",
                address(unauthorizedUser)
        ));
        strategy2nd.setlToken(address(0xdead));

        vm.expectRevert(abi.encodeWithSignature(
         "OwnableUnauthorizedAccount(address)",
                address(unauthorizedUser)
        ));
        strategy2nd.updateUnlimitedSpendingLendl(false);
        vm.stopPrank();
    }

    function testStrategies_KeeperFunctions() public {
        setUpWithFee();
        address unauthorizedUser = user1;
        // La BaseStrategy usa `_onlyKeepers` che include strategist e governance
        // Il revert esatto potrebbe variare, ma ci aspettiamo un fallimento.
        
        // --- Harvest ---
        vm.startPrank(unauthorizedUser);
        vm.expectRevert(); // Revert generico, il messaggio esatto dipende da `_onlyKeepers`
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
}
