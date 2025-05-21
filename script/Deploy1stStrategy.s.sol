// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Strategy1st} from "../contracts/Strategy1st.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Deploy is Script {
    address public owner = 0x6c64d06ef5C1da66a105893506F6Ecf8C8E191eA;
    address public vault = 0x6c64d06ef5C1da66a105893506F6Ecf8C8E191eA;


    function run() external {
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(ownerPrivateKey);

        Strategy1st  strategy1st= new Strategy1st(vault,owner);

        strategy1st.setLendingPool(0x6c64d06ef5C1da66a105893506F6Ecf8C8E191eA);//!fittizzio
        strategy1st.updateUnlimitedSpending(true);
        strategy1st.updateUnlimitedSpendingInit(true);

        vm.stopBroadcast();

    }
}
