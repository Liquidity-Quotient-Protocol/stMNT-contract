// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StMNT} from "../contracts/Vault.sol";
import {Strategy1st} from "../contracts/Strategy1st.sol";
import {Strategy2nd} from "../contracts/Strategy2nd.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IInitCore, ILendingPool as ILendingPoolInit} from "../contracts/interface/IInitCore.sol";
import {ILendingPool as ILendingPoolLendl, IProtocolDataProvider} from "../contracts/interface/ILendl.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

contract DisasterTest is Test {
    StMNT public vault;
    Strategy1st public strategy1st;
    Strategy2nd public strategy2nd;

    // --- Actors ---
    address public governance = address(1);
    address public management = address(2);
    address public treasury = address(3);
    address public guardian = address(4);
    address public user1 = address(5);
    address public user2 = address(6);
    address public user3 = address(7);
    address public whale = address(0xABC); // The actor who will drain the pool

    // --- MANTLE MAINNET ADDRESSES ---
    IWETH public constant WMNT = IWETH(0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8);

    // --- PROTOCOL ADDRESSES ---
    // Init Protocol
    address internal constant INIT_CORE = 0x972BcB0284cca0152527c4f70f8F689852bCAFc5;
    address internal constant INIT_WMNT_POOL = 0x51AB74f8B03F0305d8dcE936B473AB587911AEC4;
    address internal constant INIT_POS_MANAGER = 0x0e7401707CD08c03CDb53DAEF3295DDFb68BBa92;
    // Lendle Protocol
    address internal constant LENDLE_LENDING_POOL = 0xCFa5aE7c2CE8Fadc6426C1ff872cA45378Fb7cF3;


    function setUp() public {
        vault = new StMNT(
            address(WMNT),
            governance,
            treasury,
            "stMNT",
            "stMNT",
            guardian,
            management
        );
        vm.startPrank(governance);
        strategy1st = new Strategy1st(address(vault), governance);
        strategy1st.setLendingPool(INIT_WMNT_POOL);
        strategy1st.updateUnlimitedSpending(true);
        strategy1st.updateUnlimitedSpendingInit(true);
        strategy1st.approveLendingPool();
        strategy1st.setStrategist(management);

        strategy2nd = new Strategy2nd(address(vault), governance);
        strategy2nd.updateUnlimitedSpending(true);
        strategy2nd.setStrategist(management);


        vault.addStrategy(address(strategy1st), 4500, 0, type(uint256).max, 0);
        vault.addStrategy(address(strategy2nd), 4500, 0, type(uint256).max, 0);

        vault.setPerformanceFee(100);
        vault.setManagementFee(100);
        vault.setDepositLimit(type(uint256).max);
        vm.stopPrank();

        vm.deal(user1, 50000 ether);
        vm.deal(user2, 50000 ether);
        vm.deal(user3, 50000 ether);
    }

    // --- Helper Functions ---
    function wrapAndApprove(address user, uint256 amount) internal {
        vm.startPrank(user);
        WMNT.deposit{value: amount}();
        WMNT.approve(address(vault), amount);
        vm.stopPrank();
    }

    function depositToVault(address user, uint256 amount) internal returns (uint256) {
        vm.startPrank(user);
        uint256 shares = vault.deposit(amount, user);
        vm.stopPrank();
        return shares;
    }

    function withdrawFromVault(address user, uint256 shares) internal returns (uint256) {
        vm.startPrank(user);
        uint256 assets = vault.withdraw(shares, user, 500); // 5% max loss
        vm.stopPrank();
        return assets;
    }

    function executeHarvest() internal {
        vm.startPrank(management);
        strategy1st.harvest();
        strategy2nd.harvest();
        vm.stopPrank();
    }

    // --- Test Function ---
    function testLiquidityCrunchSchenario() public {
        setUp(); // Usa il setup di base

        console.log("\n--- Starting Liquidity Crunch Scenario ---");

        // --- PHASE 1: Normal Operation ---
        console.log("\n[PHASE 1] Users deposit funds into the vault...");
        wrapAndApprove(user1, 1000 ether);
        depositToVault(user1, 500 ether);
        wrapAndApprove(user2, 1000 ether);
        depositToVault(user2, 800 ether);

        executeHarvest(); // Le strategie investono i WMNT nel loro lending pool
        _logFullState("After initial deposits and harvest");

        uint256 wmntInInitPoolBefore = WMNT.balanceOf(INIT_WMNT_POOL);
        console.log("WMNT available in Init Lending Pool before crunch: %u", wmntInInitPoolBefore);
        assertTrue(wmntInInitPoolBefore > 0, "Init pool should have WMNT");

        skip(1 days);

        // --- PHASE 2: The Liquidity Crunch (Whale Attack using WMNT as collateral) ---
        console.log("\n\n>>>>>>>>>> [PHASE 2] WHALE ATTACK: DRAINING THE LENDING POOL <<<<<<<<<<\n");
        
        address whaleCollateralPool = INIT_WMNT_POOL; // La balena usa lo stesso pool WMNT per il collaterale
        address whaleTargetPool = INIT_WMNT_POOL;     // e per il prestito.

        // 1. La balena si procura il collaterale (molti WMNT)
        uint256 whaleCollateralAmount = 20_000 ether;
        vm.deal(whale, whaleCollateralAmount); // Diamo MNT alla balena
        
        vm.startPrank(whale);
        WMNT.deposit{value: whaleCollateralAmount}(); // La balena wrappa MNT in WMNT
        
        // 2. La balena approva Init per usare il suo WMNT
        WMNT.approve(INIT_CORE, type(uint256).max);

        // 3. La balena deposita WMNT come collaterale in Init
        uint256 whaleWmntBalance = WMNT.balanceOf(whale);
        console.log("Whale is depositing %u WMNT as collateral...", whaleWmntBalance);
        IERC20(address(WMNT)).transfer(whaleCollateralPool, whaleWmntBalance);
        uint256 wmntShares = IInitCore(INIT_CORE).mintTo(whaleCollateralPool, whale);

        // 4. La balena crea una posizione di debito e la collateralizza
        uint256 posId = IInitCore(INIT_CORE).createPos(1, whale);
        IERC20(whaleCollateralPool).transfer(INIT_POS_MANAGER, wmntShares);
        IInitCore(INIT_CORE).collateralize(posId, whaleCollateralPool);
        console.log("Whale created and collateralized position ID: %u", posId);

        // 5. LA CRISI: La balena prende in prestito TUTTI i WMNT disponibili
        uint256 availableWMNT = WMNT.balanceOf(whaleTargetPool);
        console.log("Whale is borrowing ALL available WMNT: %u", availableWMNT);
        IInitCore(INIT_CORE).borrow(whaleTargetPool, availableWMNT, posId, whale);
        vm.stopPrank();

        uint256 wmntInInitPoolAfter = WMNT.balanceOf(whaleTargetPool);
        console.log("WMNT available in Init Lending Pool AFTER crunch: %u", wmntInInitPoolAfter);
        assertLe(wmntInInitPoolAfter, 1 ether, "Pool should be empty after crunch");


        // --- PHASE 3: Testing Resilience ---
        console.log("\n\n>>>>>>>>>> [PHASE 3] TESTING VAULT RESILIENCE: USER WITHDRAWAL <<<<<<<<<<\n");
        
        uint256 user1Shares = vault.balanceOf(user1);
        console.log("User1 attempts to withdraw %u shares...", user1Shares);
        
        uint256 idleBefore = WMNT.balanceOf(address(vault));

        // Questa chiamata NON DEVE FALLIRE. Potrebbe restituire meno del previsto, ma deve completarsi.
        uint256 withdrawnAmount = withdrawFromVault(user1, user1Shares);

        console.log("Withdrawal completed. User1 received %u WMNT", withdrawnAmount);
        
        // Verifichiamo che l'utente abbia ricevuto almeno i fondi che erano idle nel vault.
        // In questo scenario, potrebbe ricevere di più se la Strategy2nd (Lendle) aveva fondi.
        assertGe(withdrawnAmount, idleBefore, "User should at least receive idle funds from vault");
        
        _logFullState("Final state after liquidity crunch and withdrawal attempt");
        console.log("\n--- Liquidity Crunch Test Completed: Vault remained operational. ---");
    }

    // Funzione helper di logging (semplificata per leggibilità)
    function _logFullState(string memory stage) internal view {
        console.log("--- State Log: [%s] ---", stage);
        console.log("Vault Total Assets: %u", vault.totalAssets());
        console.log("Vault Idle WMNT:    %u", WMNT.balanceOf(address(vault)));
        console.log("Vault Total Debt:   %u", vault.totalDebt());
        //console.log("  - Strat1 Debt: %u", vault.strategies(address(strategy1st)).totalDebt);
        //console.log("  - Strat2 Debt: %u", vault.strategies(address(strategy2nd)).totalDebt);
        console.log("-----------------------------------------");
    }
}

