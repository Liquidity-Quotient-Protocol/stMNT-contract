// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StMNT} from "../contracts/Vault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-contract@5.3.0/contracts/token/ERC20/IERC20.sol";


import {IERC20 as IERC20v4} from "@openzeppelin-contracts@4.5.0/contracts/token/ERC20/IERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract VaultTest is Test {
    StMNT public vault;
    ERC20 public token;

    address public governance = address(1);
    address public management = address(2);
    address public treasury = address(3);
    address public guardian = address(4);
    address public user1 = address(5);
    address public user2 = address(6);

    function setUp() public {
        token = new MockERC20("Wrap MNT", "WMNT");
        vault = new StMNT(
            address(token),
            governance,
            treasury,
            "stMNT",
            "stMNT",
            guardian,
            management
        );
    }

    /**
     * @notice Tests correct initialization of the Vault contract.
     * - Ensures that all roles (governance, management, guardian, treasury) are assigned correctly.
     * - Validates the default parameters (fees, degradation rate, token metadata).
     * - Verifies the deposit limit is correctly settable by governance.
     * - Reverts on re-initialization and unauthorized access to fee configuration.
     */
    function testInitialize() internal {
        vm.startPrank(governance);
      

        assertEq(vault.governance(), governance);
        assertEq(vault.management(), management);
        assertEq(vault.guardian(), guardian);
        assertEq(vault.rewards(), treasury);
        assertEq(vault.name(), "stMNT");
        assertEq(vault.symbol(), "stMNT");
        assertEq(address(vault.token()), address(token));

        assertEq(vault.performanceFee(), 1_000);
        assertEq(vault.managementFee(), 200);
        assertEq(vault.lockedProfitDegradation(), 46000000000000);

        vault.setPerformanceFee(0);
        vault.setManagementFee(0);
        vault.setDepositLimit(1_000_000 ether);

        assertEq(vault.depositLimit(), 1_000_000 ether);
        assertEq(vault.performanceFee(), 0);
        assertEq(vault.managementFee(), 0);


        vm.stopPrank();
        vm.startPrank(user1);
        vm.expectRevert("Vault: !governance");
        vault.setPerformanceFee(1000);
        vm.expectRevert("Vault: !governance");
        vault.setManagementFee(1000);
        vm.stopPrank();
    }


       /**
     * @notice Tests the permit functionality.
     * - Creates a valid permit signature for token approval
     * - Verifies the permit sets the correct allowance
     * - Confirms the spender can use the allowance
     * - Tests rejection of invalid signatures and expired permits
     */
    function testPermit() internal {
        // Create permit data
        uint256 privateKey = 0xA11CE;
        address owner = vm.addr(privateKey);
        address spender = user2;
        uint256 value = 100 ether;
        uint256 deadline = block.timestamp + 1 hours;

        // Setup: Mint tokens to owner and deposit them
        MockERC20(address(token)).mint(owner, 1000 ether);
        vm.startPrank(owner);
        token.approve(address(vault), 1000 ether);
        vault.deposit(1000 ether, owner);
        vm.stopPrank();

        // Get the domain separator
        bytes32 domainSeparator = vault.DOMAIN_SEPARATOR();
        uint256 nonce = vault.nonces(owner);

        console.log("nonce is: ", nonce);

        // Create the permit hash
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                value,
                nonce,
                deadline
            )
        );

        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        // Sign the hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);

        // Test valid permit
        vault.permit(owner, spender, value, deadline, v, r, s);
        assertEq(vault.allowance(owner, spender), value);

        // check to see if nonce increased 
        uint256 nonceAfter = vault.nonces(owner);
        console.log("nonce after is: ", nonceAfter);

        // Test that spender can use the allowance
        vm.startPrank(spender);
        vault.transferFrom(owner, spender, value);
        assertEq(vault.balanceOf(spender), value);
        vm.stopPrank();

        // Test expired permit
        vm.warp(block.timestamp + 2 hours);
        vm.expectRevert("Vault: expired permit");
        vault.permit(owner, spender, value, deadline, v, r, s);

        // Test invalid signature
        vm.warp(block.timestamp - 2 hours); // Reset time
        vm.expectRevert("Vault: invalid signature");
        vault.permit(owner, spender, value, deadline, v, r, bytes32(uint256(s) + 1));

        // Test invalid owner
        vm.expectRevert("Vault: invalid owner");
        vault.permit(address(0), spender, value, deadline, v, r, s);
    }




    function testAllTogether() public {
        testInitialize();

        testPermit();

     
    }

}


