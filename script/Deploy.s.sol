// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {StMNT} from "../contracts/Vault.sol";
import {Strategy1st} from "../contracts/Strategy1st.sol";
import {Strategy2nd} from "../contracts/Strategy2nd.sol";

contract DeployScript is Script {

    // --- CONFIGURAZIONE DEGLI INDIRIZZI PER IL DEPLOYMENT ---
    
    address public governance = 0xFE6Ab935dc341FEe5A32970Ea2FC48a13d4af36d; 
    address public management = 0x128C8b0Aa97e8A68630b4d5a917bCB68820a49BE; 
    address public treasury = 0x82f9a9EAeE61DDe2128F41054758a2eCa580413A;   
    address public guardian = 0x1EdF43614f1B7B448a330a6284Bf36037b17aac9;  
    address public keeper = 0x6c1Ad07DA4C95c3D9Da4174F52C87401e9Ca3098; 
    address public strategist = 0x2b506Fb4c70848D38Aed2e6715f65500CDa88Ba9;
    
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
            deployerAddress,//governance,
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
        strategy1st.setKeeper(keeper);
        strategy1st.setRewards(treasury);
        strategy1st.setStrategist(strategist);


        strategy2nd.setStrategist(management);
        strategy2nd.setKeeper(keeper);
        strategy2nd.setRewards(treasury);
        strategy2nd.setStrategist(strategist);
        
        vm.stopBroadcast();
        
        // --- 5. CONFIGURAZIONE FINALE (eseguita dalla GOVERNANCE) ---
        console.log("Broadcasting from GOVERNANCE address to add strategies...");
        uint256 governancePrivateKey = vm.envUint("GOVERNANCE_PRIVATE_KEY");
        vm.startBroadcast(governancePrivateKey);

        console.log("Adding Strategy1st to Vault...");
        vault.addStrategy(
            address(strategy1st),
            5000, // 50% debt ratio
            0,
            type(uint256).max,
            0 
        );

        console.log("Adding Strategy2nd to Vault...");
        vault.addStrategy(
            address(strategy2nd),
            3000, // 30% debt ratio
            0,
            type(uint256).max,
            0
        );

        console.log("Setting final vault fees...");
        vault.setPerformanceFee(1000); // 10%
        vault.setManagementFee(0);  // 0%
        vault.setDepositLimit(type(uint256).max);

        //vault.setGovernance(governance);

        vm.stopBroadcast();
        
        console.log("Deployment and configuration complete!");
    }
}
