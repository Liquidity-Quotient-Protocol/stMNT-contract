// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Vault} from "../contracts/Vault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract VaultTest is Test {
    Vault public vault;
    ERC20 public token;

    address public governance = address(1);
    address public management = address(2);
    address public treasury = address(3);
    address public guardian = address(4);
    address public user1 = address(5);
    address public user2 = address(6);

    function setUp() public {
        token = new MockERC20("Wrap MNT", "WMNT");
        vault = new Vault();
    }

    function testInitialize() internal {
        vm.startPrank(governance);
        vault.initialize(
            address(token),
            governance,
            treasury,
            "Staked Mantle Vault",
            "sMNT",
            guardian,
            management
        );

        assertEq(vault.governance(), governance);
        assertEq(vault.management(), management);
        assertEq(vault.guardian(), guardian);
        assertEq(vault.rewards(), treasury);
        assertEq(vault.name(), "Staked Mantle Vault");
        assertEq(vault.symbol(), "sMNT");
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

        vm.expectRevert();
        vault.initialize(
            address(token),
            governance,
            treasury,
            "Staked Mantle Vault",
            "sMNT",
            guardian,
            management
        );
        vm.stopPrank();
        vm.startPrank(user1);
        vm.expectRevert("Vault: !governance");
        vault.setPerformanceFee(1000);
        vm.expectRevert("Vault: !governance");
        vault.setManagementFee(1000);
        vm.stopPrank();
    }

    function testDepositAndWithdraw() internal {
        MockERC20(address(token)).mint(user1, 1_000 ether);
        vm.startPrank(user1);
        token.approve(address(vault), 1000 ether);
        uint256 shares = vault.deposit(1000 ether, user1);
        assertEq(shares, 1000 ether);
        vault.approve(address(vault), 1 ether);
        uint256 assets = vault.withdraw(shares, user1, 100);
        assertEq(assets, 1000 ether);
        vm.stopPrank();
    }

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

    function testAllTogether() public {
        testInitialize();
        console.log("testInitialize");
        testDepositAndWithdraw();
        console.log("testDepositAndWithdraw");
        testDepositAndWithdrawMultiUser();
        console.log("testDepositAndWithdrawMultiUser");
    }
}

/*
💰 Deposito



Un utente può depositare type(uint256).max e viene calcolato correttamente.

Dopo un deposito:

Lo share balanceOf(user) è aggiornato.

totalSupply è aggiornato.

    totalIdle è aggiornato.

    Evento Deposit è emesso correttamente.

🧾 Prelievo



withdraw() fallisce se si tenta di ritirare più di balanceOf(user).

Dopo un withdraw():

balanceOf(user) diminuisce correttamente.

totalSupply è aggiornato.

    totalIdle è aggiornato.

    Evento Withdraw è emesso correttamente.

🔁 Transfer / Approve / Allowance

transfer() sposta correttamente le share tra utenti.

transferFrom() funziona con approve() e aggiorna allowance.

increaseAllowance() e decreaseAllowance() modificano il valore correttamente.

    Eventi Transfer e Approval sono emessi.

🧾 ERC20 Metadata

totalSupply() restituisce il totale corretto.

balanceOf() è consistente per ogni utente.

allowance(), approve() funzionano come da standard.

    pricePerShare() è 1e18 se non ci sono strategie né locked profit.

🔐 Sicurezza / Permissioning

Solo governance può:

setGovernance(), acceptGovernance()

setManagement(), setRewards(), setGuardian()

setPerformanceFee(), setManagementFee()

    setDepositLimit()

setEmergencyShutdown(true) può essere chiamato solo da governance o guardian.

    setEmergencyShutdown(false) solo da governance.

🧠 Logica interna

_calculateLockedProfit() restituisce il valore corretto dopo X blocchi.

_shareValue(shares) e _sharesForAmount(amount) sono coerenti e inversi.

maxAvailableShares() restituisce solo totalIdle se non ci sono strategie.

    availableDepositLimit() riflette correttamente depositLimit - totalAssets.

🧹 Sweep

sweep(token) restituisce i token estranei a governance.

    Non è possibile sweep() il token gestito (token) se non in eccesso.

🧪 Extra Bonus (non urgenti per fedeltà, ma consigliati)

Test di permit() con firma off-chain (EIP-2612).

Test di eventi duplicati (Transfer, Approval) non presenti più di una volta.

    Gas usage su deposit() e withdraw() coerente (benchmark yearn).

🛠️ Setup test consigliato

    Mock token ERC20 (18 decimali)

    Utente A (depositor), Utente B (recipient)

    Ruoli: governance, guardian, management, rewards

📦 Test Strategy (quando la aggiungerai)

addStrategy() registra correttamente i parametri.

report(gain/loss/debt) aggiorna i contatori e i fondi correttamente.

migrateStrategy() sposta lo stato e i fondi.

    revokeStrategy() azzera i limiti ma mantiene la posizione.

 */
