// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StMNT} from "../contracts/Vault.sol";
import {Strategy2nd} from "../contracts/Strategy2nd.sol"; // MODIFICATO per usare Strategy2nd
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// L'interfaccia ILendl è necessaria per Strategy2nd per le conversioni e per ottenere lTokenWMNT
import {IProtocolDataProvider, ILendingPool} from "../contracts/interface/ILendl.sol";


interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

contract Strg2MultiUserTest is Test { // Rinominato il contratto di test
    StMNT public vault;
    Strategy2nd public strategy2nd; // MODIFICATO per usare Strategy2nd

    address public governance = address(1);
    address public management = address(2);
    address public treasury = address(3);
    address public guardian = address(4);
    
    address public userA = address(0xA); // Utente A
    address public userB = address(0xB); // Utente B
    address public userC = address(0xC); // Utente C

    IWETH public constant WMNT =
        IWETH(address(0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8));
    
    // LENDING_POOL_ADDRESS per Strategy2nd (Lendle)
    // Questo è l'indirizzo del LendingPool principale di Lendle, non l'lToken.
    address public constant LENDLE_POOL_ADDRESS = 0xCFa5aE7c2CE8Fadc6426C1ff872cA45378Fb7cF3;


    function setUp() public {
        vault = new StMNT(
            address(WMNT),
            governance,
            treasury,
            "stMNT_Multi2", 
            "stMNT_Multi2",
            guardian,
            management
        );
        
        // Setup per Strategy2nd
        vm.startPrank(governance);
        strategy2nd = new Strategy2nd(address(vault), governance);
        // In Strategy2nd, lendingPool è una costante e lTokenWMNT è determinato nel costruttore.
        // Non c'è setLendingPool da chiamare.
        
        strategy2nd.updateUnlimitedSpending(true); // Strategia approva vault per 'want' (WMNT)
        // L'approve per il lendingPool di Lendle per spendere WMNT dalla strategia
        // è già fatto nel costruttore di Strategy2nd.
        // strategy2nd.updateUnlimitedSpendingLendl(true); // Questo è ridondante.
        
        vault.addStrategy(
            address(strategy2nd),
            10_000, 
            0,      
            type(uint256).max, 
            0       
        );
        vault.setPerformanceFee(0); 
        vault.setManagementFee(0);  
        vault.setDepositLimit(type(uint256).max); 
        vm.stopPrank();

        // Fornisci fondi iniziali agli utenti
        vm.deal(userA, 5000 ether);
        vm.deal(userB, 5000 ether);
        vm.deal(userC, 5000 ether);
    }

    function wrapAndApprove(address user, uint256 amount) internal {
        vm.startPrank(user);
        WMNT.deposit{value: amount}();
        WMNT.approve(address(vault), amount);
        vm.stopPrank();
    }

    function depositToVault(address user, uint256 amount) internal returns (uint256 shares) {
        vm.startPrank(user);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
        console.log("User %a deposited %u WMNT, received %u shares.", user, amount, shares);
        console.log("PPS after deposit: %u", vault.pricePerShare()); // Modificato "PPS : u%"
    
    }

    function withdrawFromVault(address user, uint256 sharesToWithdraw) internal returns (uint256 assets) {
        // Leggi il bilancio di quote dell'utente PRIMA del prelievo per il log
        uint256 userSharesBefore = vault.balanceOf(user);
        require(sharesToWithdraw <= userSharesBefore, "Attempting to withdraw more shares than owned");

        vm.startPrank(user);
        assets = vault.withdraw(sharesToWithdraw, user, 100); // maxLoss 0.01%
        vm.stopPrank();
        console.log("User %a withdrew %u shares (had %s), received %u WMNT.", user, sharesToWithdraw, userSharesBefore);
        console.log("WMNT ", assets);
        console.log("PPS after withdrawal: %u", vault.pricePerShare()); // Modificato "PPS : u%"
    }

    function executeHarvest(string memory label) internal { // Aggiunto label per chiarezza nei log
        console.log("--- Executing Harvest [%s] ---", label);
        vm.startPrank(management);
        strategy2nd.harvest();
        vm.stopPrank();
        console.log("Harvest [%s] executed. Current PPS: %u", label, vault.pricePerShare());
    }

    // Per Strategy2nd (Lendle/Aave-like), non c'è una funzione accrueInterest() esplicita da chiamare sul pool.
    // Gli interessi si accumulano e sono riflessi dal normalizedIncome.
    // Questa funzione ora loggherà solo il valore stimato.
    function logLendleValue(string memory occasion) internal {
        console.log("--- Logging Lendle Value: [%s] ---", occasion);
        uint256 actualLTokens = IERC20(strategy2nd.lTokenWMNT()).balanceOf(address(strategy2nd));
        if (actualLTokens > 0) {
            // Usiamo la funzione lTokenToWant della strategia, che usa getReserveNormalizedIncome
            uint256 valueInWant = strategy2nd.lTokenToWant(actualLTokens);
            console.log("Lendle - Strategy holds %s lTokens, valued at: %s WMNT (via lTokenToWant)", actualLTokens, valueInWant);
        } else {
            console.log("Lendle - Strategy holds 0 lTokens.");
        }
    }


    function testMultiUser_MixedOperations_LendleInterest() public { // Nome test specifico per Strategy2nd
        console.log("--- Starting Multi-User Test for Strategy2nd (Lendle) ---");

        uint256 depositA1 = 1000 ether;
        uint256 depositB1 = 1500 ether;

        // ----- FASE 1: Depositi Iniziali e Primo Harvest -----
        console.log("--- Phase 1: Initial Deposits & First Harvest ---");
        wrapAndApprove(userA, depositA1);
        uint256 sharesA1 = depositToVault(userA, depositA1);
        
        wrapAndApprove(userB, depositB1);
        uint256 sharesB1 = depositToVault(userB, depositB1);

        executeHarvest("H1 - After A & B Deposit"); 
        uint256 pps_after_harvest1 = vault.pricePerShare();
        logLendleValue("After H1");

        // ----- FASE 2: Periodo di Interesse e Nuovo Deposito -----
        console.log("--- Phase 2: Interest Period & New Deposit (User C) ---");
        skip(30 days); 
        logLendleValue("After 30d skip (before H2)"); // Per vedere l'effetto degli interessi in Lendle

        executeHarvest("H2 - Report 1st Profit"); // La strategia riporta profitto, che viene "bloccato"
        
        uint256 pps_after_profit_report_locked = vault.pricePerShare();
        console.log("PPS immediately after H2 (profit locked): %u", pps_after_profit_report_locked);
        // Qui il PPS non dovrebbe essere aumentato drasticamente rispetto a pps_after_harvest1

        skip(8 hours); // Permetti al locked profit di sbloccarsi
        uint256 pps_after_profit_unlock1 = vault.pricePerShare();
        console.log("PPS after 1st profit unlock time (after H2): %u", pps_after_profit_unlock1);
        assertTrue(pps_after_profit_unlock1 > pps_after_harvest1, "PPS1: PPS should increase after profit unlock");

        uint256 depositC1 = 800 ether;
        wrapAndApprove(userC, depositC1);
        uint256 sharesC1 = depositToVault(userC, depositC1); // UserC deposita con il nuovo PPS (pps_after_profit_unlock1)
        logLendleValue("After User C Deposit");

        // ----- FASE 3: Prelievi e Altro Periodo di Interesse -----
        console.log("--- Phase 3: Partial Withdrawal (User A) & Another Interest Period ---");
        uint256 sharesToWithdrawA = sharesA1 / 2;
        uint256 assetsA_partial_withdrawal = withdrawFromVault(userA, sharesToWithdrawA); 
        // Calcolo del valore atteso per il prelievo parziale di A
        uint256 expectedAssetsA_partial = (sharesToWithdrawA * pps_after_profit_unlock1) / 1 ether;
        assertApproxEqRel(assetsA_partial_withdrawal, expectedAssetsA_partial, 100, "UserA partial withdrawal amount mismatch"); // Tolleranza 0.01%
        // assertTrue(assetsA_partial_withdrawal > depositA1 / 2, "UserA partial withdrawal should reflect some profit");

        skip(30 days);
        logLendleValue("After another 30d skip (before H3)");

        executeHarvest("H3 - Report 2nd Profit"); 
        
        uint256 pps_after_profit_report2_locked = vault.pricePerShare();
        skip(8 hours); 
        uint256 pps_after_profit_unlock2 = vault.pricePerShare();
        console.log("PPS after 2nd profit unlock time (after H3): %u", pps_after_profit_unlock2);
        assertTrue(pps_after_profit_unlock2 > pps_after_profit_unlock1, "PPS2: PPS should increase further");

        // ----- FASE 4: Prelievi Finali -----
        console.log("--- Phase 4: Final Withdrawals ---");
        uint256 remainingSharesA = vault.balanceOf(userA);
        uint256 assetsA_final = withdrawFromVault(userA, remainingSharesA); 
        
        uint256 assetsB_final = withdrawFromVault(userB, sharesB1);
        uint256 assetsC_final = withdrawFromVault(userC, sharesC1);

        // Calcolo dei profitti totali
        uint256 totalWithdrawnA = assetsA_partial_withdrawal + assetsA_final;
        
        console.log("UserA: Deposited %s, Withdrew Total %s", depositA1, totalWithdrawnA);
        console.log("UserB: Deposited %s, Withdrew Total %s", depositB1, assetsB_final);
        console.log("UserC: Deposited %s, Withdrew Total %s", depositC1, assetsC_final);

        assertTrue(totalWithdrawnA > depositA1, "UserA total withdrawal should be > initial deposit");
        assertTrue(assetsB_final > depositB1, "UserB total withdrawal should be > initial deposit");
        // Per UserC, il profitto dipende molto da quando è entrato rispetto agli aumenti di PPS
        // e da quanto interesse è maturato mentre i suoi fondi erano dentro.
        // Se pps_after_profit_unlock2 > pps con cui C è entrato, allora C dovrebbe avere profitto.
        uint256 pps_at_C_deposit = (depositC1 * 1 ether) / sharesC1; // Stima del PPS al momento del deposito di C
        if (pps_after_profit_unlock2 > pps_at_C_deposit) {
             assertTrue(assetsC_final > depositC1, "UserC total withdrawal should be > initial deposit if PPS increased");
        } else {
            assertApproxEqRel(assetsC_final, depositC1, 100, "UserC withdrawal if no significant PPS change for C");
        }


        assertTrue(totalWithdrawnA + assetsB_final > depositA1 + depositB1, "Combined profit for UserA & B not realized");

        console.log("SUCCESS: Multi-user test for Strategy2nd with mixed operations and interest completed.");
    }
}