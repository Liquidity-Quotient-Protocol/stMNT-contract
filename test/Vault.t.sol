// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/Vault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol)
        ERC20(name, symbol)
    {}
}

contract VaultTest is Test {
    Vault public vault;
    ERC20 public token;

    address public governance = address(1);
    address public management = address(2);
    address public user = address(3);

    function setUp() public {
        token = new MockERC20("Mock Token", "MOCK");
        vault = new Vault();
    }

    function testDepositAndWithdraw() public {
        vm.prank(user);
        token.approve(address(vault), 1000 ether);

        vm.prank(user);
        uint256 shares = vault.deposit(1000 ether, user);

        assertGt(shares, 0);

        vm.prank(user);
        uint256 assets = vault.withdraw(shares, user, 1);

        assertGt(assets, 0);
    }
}
