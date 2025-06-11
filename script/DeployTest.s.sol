// SPDX-License-Identifier: MIT
pragma solidity 0.8.19; // ✅ Cambia a ^0.8.19
import "forge-std/Script.sol";
import {StMNT} from "../contracts/Vault.sol";
import {Liquid} from "../contracts/LiqToken.sol";
import {MockWnt, MockERC20} from "../contracts/mockWMNT.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DeployTest is Script {
    address public owner = 0x6c64d06ef5C1da66a105893506F6Ecf8C8E191eA;
    ERC20 public token;

    function run() external {
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(ownerPrivateKey);

        token = new MockERC20("Wrap MNT", "WMNT");
        MockERC20(address(token)).mint(owner, 1_000 ether);

        StMNT stMNT = new StMNT(
            //address(0x791c0D8cD4A1B2c3Cb00234a4bc1CA647dbc260f),
            address(token),
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

        //console.log("MockWnt deployed at:", address(mockWnt));
        console.log("StMNT vault deployed at:", address(stMNT));

        vm.stopBroadcast();
    }
}
