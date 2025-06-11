// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {StMNT} from "../contracts/Vault.sol";
import {Strategy1st} from "../contracts/Strategy1st.sol";
import {Strategy2nd} from "../contracts/Strategy2nd.sol";

contract DeployScript is Script {

    // --- CONFIGURAZIONE DEGLI INDIRIZZI PER IL DEPLOYMENT ---
    
    address public governance = 0x6c64d06ef5C1da66a105893506F6Ecf8C8E191eA; 
    address public management = 0x6c64d06ef5C1da66a105893506F6Ecf8C8E191eA; 
    address public treasury = 0x6c64d06ef5C1da66a105893506F6Ecf8C8E191eA;   
    address public guardian = 0x6c64d06ef5C1da66a105893506F6Ecf8C8E191eA;   
    
    // --- INDIRIZZI DEI CONTRATTI SU MANTLE MAINNET ---
    address public constant WMNT_ADDRESS = 0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8;
    address public constant INIT_LENDING_POOL = 0x44949636f778fAD2b139E665aee11a2dc84A2976;

    function run() external {
 
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

    
        vm.startBroadcast(deployerPrivateKey);

        // 1. DEPLOY DEL VAULT
        console.log("Deploying StMNT Vault...");
        StMNT vault = new StMNT(
            WMNT_ADDRESS,
            governance,
            treasury,
            "stMNT",
            "stMNT",       
            guardian,
            management
        );
        console.log("Vault deployed at:", address(vault));

        // 2. DEPLOY DELLE STRATEGIE
      
        console.log("Deploying Strategy1st (Init Protocol)...");
        Strategy1st strategy1st = new Strategy1st(address(vault),governance);
        console.log("Strategy1st deployed at:", address(strategy1st));

        console.log("Deploying Strategy2nd (Lendle)...");
        Strategy2nd strategy2nd = new Strategy2nd(address(vault),governance);
        console.log("Strategy2nd deployed at:", address(strategy2nd));

        // 3. CONFIGURAZIONE DELLE STRATEGIE
  
        console.log("Configuring Strategy1st...");
        strategy1st.setLendingPool(INIT_LENDING_POOL);
        strategy1st.approveLendingPool(); 

        // 4. DECENTRALIZZAZIONE DEI RUOLI
        console.log("Setting 'management' as strategist for both strategies...");
        strategy1st.setStrategist(management);
        strategy2nd.setStrategist(management);
        
        vm.stopBroadcast();
        
        // --- 5. CONFIGURAZIONE FINALE (eseguita dalla GOVERNANCE) ---
        console.log("Broadcasting from GOVERNANCE address to add strategies...");
        uint256 governancePrivateKey = vm.envUint("GOVERNANCE_PRIVATE_KEY");
        vm.startBroadcast(governancePrivateKey);

        console.log("Adding Strategy1st to Vault...");
        vault.addStrategy(
            address(strategy1st),
            4500, // 45% debt ratio
            0,
            type(uint256).max,
            0 
        );

        console.log("Adding Strategy2nd to Vault...");
        vault.addStrategy(
            address(strategy2nd),
            4500, // 45% debt ratio
            0,
            type(uint256).max,
            0
        );
        
        console.log("Setting final vault fees...");
        vault.setPerformanceFee(100); // 1%
        vault.setManagementFee(100);  // 1%
        vault.setDepositLimit(type(uint256).max);

        vm.stopBroadcast();
        
        console.log("Deployment and configuration complete!");
    }
}
