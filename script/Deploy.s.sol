// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {StMNT} from "../contracts/Vault.sol";
import {Liquid} from "../contracts/LiqToken.sol";
import {MockWnt} from "../contracts/mockWMNT.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Deploy is Script {
    address public owner = 0x6c64d06ef5C1da66a105893506F6Ecf8C8E191eA;

    function run() external {
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(ownerPrivateKey);

        StMNT stMNT = new StMNT();
        Liquid LIQ = new Liquid(owner);
        MockWnt mockWnt = new MockWnt(owner);

        mockWnt.mint(owner, 1_000_000 ether);

        address token = address(mockWnt);

        stMNT.initialize(
            address(0xc0205beC85Cbb7f654c4a35d3d1D2a96a2217436),
            owner,
            owner,
            "stMNT",
            "stMNT",
            owner,
            owner
        );

        stMNT.setPerformanceFee(0);
        stMNT.setManagementFee(0);
        stMNT.setDepositLimit(1_000_000 ether);

        vm.stopBroadcast();

    }
}
