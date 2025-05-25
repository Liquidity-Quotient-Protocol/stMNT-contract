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
     * @notice Tests a single user's full deposit and withdrawal lifecycle.
     * - User deposits 1000 tokens and receives 1000 shares.
     * - Verifies that pricePerShare remains 1e18 (no strategy).
     * - Withdraws all shares and receives original amount.
     * - Attempting a second withdrawal reverts (no remaining shares).
     */
    function testDepositAndWithdraw() internal {
        MockERC20(address(token)).mint(user1, 1_000 ether);
        vm.startPrank(user1);
        token.approve(address(vault), 1000 ether);
        uint256 shares = vault.deposit(1000 ether, user1);
        assertEq(shares, 1000 ether);
        assertEq(vault.pricePerShare(), 1 ether);
        vault.approve(address(vault), 1 ether);
        uint256 assets = vault.withdraw(shares, user1, 100);
        assertEq(assets, 1000 ether);

        vault.approve(address(vault), 1 ether);
        vm.expectRevert();
        vault.withdraw(shares, user1, 100);
        vm.stopPrank();
    }

    /**
     * @notice Tests deposits and withdrawals across multiple users.
     * - User1 and User2 both deposit 1000 tokens.
     * - Validates totalSupply and totalIdle increase accordingly.
     * - Each user is able to withdraw their full balance.
     * - Final state assertions ensure internal accounting is reset.
     */
    function testDepositAndWithdrawMultiUser() internal {
        // Mint 1000 tokens to each user
        //User1 balance 1000 token
        MockERC20(address(token)).mint(user2, 1000 ether);
        assertEq(token.balanceOf(user2), 1000 ether);
        // Setup approvals
        vm.startPrank(user1);
        token.approve(address(vault), 1000 ether);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(vault), 1000 ether);
        vm.stopPrank();

        // User1 deposits 1000 ether
        vm.startPrank(user1);
        uint256 sharesUser1 = vault.deposit(1000 ether, user1);
        assertEq(sharesUser1, 1000 ether);
        vm.stopPrank();

        // User2 deposits 1000 ether — now total vault assets are 2000
        vm.startPrank(user2);
        uint256 sharesUser2 = vault.deposit(1000 ether, user2);
        assertEq(sharesUser2, 1000 ether); // should still be 1:1 since no strategy or lockedProfit
        vm.stopPrank();

        // Verify total supply and totalIdle
        assertEq(vault.totalSupply(), 2000 ether);
        assertEq(vault.totalIdle(), 2000 ether);

        // User1 withdraws all shares
        vm.startPrank(user1);
        uint256 assets1 = vault.withdraw(sharesUser1, user1, 100);
        assertEq(assets1, 1000 ether);
        vm.stopPrank();

        // User2 withdraws all shares
        vm.startPrank(user2);
        uint256 assets2 = vault.withdraw(sharesUser2, user2, 100);
        assertEq(assets2, 1000 ether);
        vm.stopPrank();

        // Final checks
        assertEq(token.balanceOf(user1), 1000 ether);
        assertEq(token.balanceOf(user2), 1000 ether);
        assertEq(vault.totalIdle(), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.balanceOf(user1), 0);
        assertEq(vault.balanceOf(user2), 0);
    }

    /**
     * @notice Tests the transfer of vault shares between users.
     * - User1 deposits 10 tokens and receives 10 shares.
     * - Shares are transferred to User2.
     * - User2 withdraws the shares and receives corresponding tokens.
     * - Final balance check confirms accuracy.
     */
    function testTransfertShare() internal {
        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(token.balanceOf(user2), 1000 ether);

        vm.startPrank(user1);
        token.approve(address(vault), 10 ether);
        uint256 shares = vault.deposit(10 ether, user1);
        vault.transfer(user2, shares);
        assertEq(vault.balanceOf(user1), 0);
        assertEq(vault.balanceOf(user2), shares);
        vm.stopPrank();

        assertEq(token.balanceOf(address(vault)), 10 ether);

        vm.startPrank(user2);
        token.approve(address(vault), shares);
        uint256 assets = vault.withdraw(shares, user2, 100);
        assertEq(assets, 10 ether);
        assertEq(vault.balanceOf(user2), 0);

        assertEq(token.balanceOf(user2), 1010 ether);
        vm.stopPrank();
    }

    /**
     * @notice Tests ERC20 `transferFrom()` for the underlying token.
     * - User1 approves User2 to transfer tokens on their behalf.
     * - User2 executes a `transferFrom()` and receives tokens.
     * - Validates allowance is consumed and balances updated.
     */
    function testTransfertFromToken() internal {
        assertEq(token.balanceOf(user2), 1010 ether);
        uint balanceUser2 = token.balanceOf(user2);

        vm.startPrank(user1);
        uint beforeAllowance = token.allowance(user1, user2);
        assertEq(beforeAllowance, 0);
        token.approve(address(user2), 10 ether);
        uint afterAllowance = token.allowance(user1, user2);
        assertEq(afterAllowance, 10 ether);
        uint balanceUser1 = token.balanceOf(user1);
        vm.stopPrank();

        vm.startPrank(user2);
        token.transferFrom(user1, user2, 10 ether);
        uint beforeAllowance2 = token.allowance(user1, user2);
        assertEq(beforeAllowance2, 0);
        assertEq(token.balanceOf(user1), balanceUser1 - 10 ether);
        assertEq(token.balanceOf(user2), balanceUser2 + 10 ether);

        vm.stopPrank();
    }

    /**
     * @notice Tests share allowances and `transferFrom()` logic for the Vault token.
     * - User1 deposits shares and sets an allowance for User2.
     * - User2 increases/decreases allowance and performs a transferFrom.
     * - Ensures allowance is consumed and balances are updated correctly.
     */
    function testTransfertFromShare() internal {
        uint balanceUser2 = vault.balanceOf(user2);

        vm.startPrank(user1);
        token.approve(address(vault), 10 ether);
        uint256 shares = vault.deposit(10 ether, user1);
        assertEq(shares, 10 ether);

        vault.approve(user2, 1 ether);
        assertEq(vault.allowance(user1, user2), 1 ether);
        vault.increaseAllowance(user2, 1 ether);
        assertEq(vault.allowance(user1, user2), 2 ether);
        vault.decreaseAllowance(user2, 1 ether);
        assertEq(vault.allowance(user1, user2), 1 ether);
        vm.stopPrank();

        vm.startPrank(user2);
        vault.transferFrom(user1, user2, 0.5 ether);
        assertEq(vault.allowance(user1, user2), 0.5 ether);
        assertEq(vault.balanceOf(user1), 9.5 ether);
        assertEq(vault.balanceOf(user2), balanceUser2 + 0.5 ether);
        vm.stopPrank();
    }

    /**
     * @notice Verifies that `lockedProfit()` is zero when no strategy report has occurred.
     * - Ensures the vault starts with no locked profit unless explicitly reported.
     * - Important baseline check for profit-locking logic.
     */
    function testLockedProfitZeroWithoutReport() internal view {
        assertEq(vault.lockedProfit(), 0);
    }

    /**
     * @notice Tests the ability to sweep unrelated (non-vault) tokens from the vault.
     * - An attacker mints a fake token to the Vault.
     * - Governance is able to sweep the fake token out.
     * - Ensures the Vault complies with the Yearn `sweep()` pattern.
     * - Protects against dust accumulation or accidental transfers.
     */
    function testSweepOtherToken() internal {
        address attacker = address(123);
        vm.startPrank(attacker);
        ERC20 fake = new MockERC20("Fake", "FAKE");
        MockERC20(address(fake)).mint(address(vault), 100 ether);
        vm.stopPrank();
        vm.prank(governance);
        vault.sweep(address(fake), type(uint256).max);
        assertEq(fake.balanceOf(governance), 100 ether);
    }

    /**
     * @notice Ensures that the Vault's own managed token cannot be swept.
     * - User deposits tokens into the Vault (making them "managed").
     * - Governance attempts to sweep Vault's own token and reverts.
     * - Enforces a critical invariant: managed tokens are not sweepable unless in excess.
     */
    function testCannotSweepVaultToken() internal {
        vm.startPrank(user1);
        token.approve(address(vault), 1 ether);
        vault.deposit(1 ether, user1);
        vm.stopPrank();

        vm.prank(governance);
        vm.expectRevert("Vault: no excess vault token");
        vault.sweep(address(token), type(uint256).max);
    }

    function testAllTogether() public {
        // ✅ Initializes the Vault and verifies core parameters
        testInitialize();

        // ✅ Single user deposit and withdrawal test
        testDepositAndWithdraw();

        // ✅ Multi-user deposits and withdrawals; share accounting consistency
        testDepositAndWithdrawMultiUser();

        // ✅ Tests share transfers between users
        testTransfertShare();

        // ✅ Tests token.transferFrom() and token allowance behavior
        testTransfertFromToken();

        // ✅ Tests vault.transferFrom() and share allowance behavior
        testTransfertFromShare();

        // ✅ Verifies that locked profit remains zero without any strategy reports
        testLockedProfitZeroWithoutReport();

        // ✅ Positive sweep() test: allows sweeping unrelated tokens
        testSweepOtherToken();

        // ✅ Negative sweep() test: cannot sweep Vault's own token unless it's excess
        testCannotSweepVaultToken();
    }

       /**
     * @notice Tests the permit functionality.
     * - Creates a valid permit signature for token approval
     * - Verifies the permit sets the correct allowance
     * - Confirms the spender can use the allowance
     * - Tests rejection of invalid signatures and expired permits
     */
    function testPermit() external {
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
}


