// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StMNT} from "../contracts/Vault.sol";
import {Strategy3rd} from "../contracts/Strategy3rd.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRSM} from "../contracts/interface/RsmInterface.sol";
import {ILendingPool, IProtocolDataProvider} from "../contracts/interface/ILendl.sol";

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256) external;

    function approve(address, uint256) external returns (bool);

    function transfer(address, uint256) external returns (bool);

    function balanceOf(address) external view returns (uint256);
}

// Crea un mock che simula solo le funzioni che ti servono
contract MockStakingMNT {
    mapping(address => uint256) public deposited;

    function deposit(uint256 assets) external payable returns (uint256) {
        deposited[msg.sender] += msg.value;
        return msg.value;
    }

    function withdraw(
        uint256 assets,
        address receiver
    ) external returns (uint256) {
        require(deposited[msg.sender] >= assets, "Insufficient balance");
        deposited[msg.sender] -= assets;
        payable(receiver).transfer(assets);
        return assets;
    }
}

contract Strg2WithInterestLogging is Test {
    StMNT public vault;
    Strategy3rd public strategy3rd;

    IRSM constant RSM = IRSM(0x9cdbDe30E4F3F0f0E4Ead9d7074BEBCB99dDAD9B);

    address public governance = address(1);
    address public management = address(2);
    address public treasury = address(3);
    address public guardian = address(4);
    address public user1 = address(5);

    IWETH public constant WMNT =
        IWETH(address(0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8));

    MockStakingMNT public mRSM = new MockStakingMNT();

    function setUp() internal {
        vault = new StMNT(
            address(WMNT),
            governance,
            treasury,
            "stMNT_Test",
            "stMNT_Test",
            guardian,
            management
        );

        vm.startPrank(governance);
        strategy3rd = new Strategy3rd(address(vault), governance, 0);

        strategy3rd.updateUnlimitedSpending(true);
        vault.addStrategy(
            address(strategy3rd),
            10_000, // 100% debtRatio
            0, // minDebtPerHarvest
            type(uint256).max, // maxDebtPerHarvest
            0 // performanceFee
        );
        vault.setPerformanceFee(0);
        vault.setManagementFee(0);
        vault.setDepositLimit(type(uint256).max);

        //! solo per il test
        strategy3rd.setMockTest(address(mRSM));

        vm.stopPrank();

        vm.deal(user1, 5000 ether);
    }

    function wrapMNT(uint256 _amount) internal {
        WMNT.deposit{value: _amount}();
    }

    function testDepositAndWithdraw_WithStrategy_WithInterest_DetailedLogs()
        public

    {
        setUp();
        console.log(
            "====== Starting Detailed Interest Test for Strategy3rd ======"
        );
        uint256 depositAmount = 1000 ether;

        // --- FASE 1: DEPOSITO UTENTE ---
        console.log("--- Phase 1: User1 Deposit ---");
        vm.startPrank(user1);
        wrapMNT(depositAmount);
        WMNT.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user1);
        console.log(
            "User1 deposited %s WMNT, received %s shares",
            depositAmount,
            shares
        );
        vm.stopPrank();

        // --- FASE 2: PRIMO HARVEST ---
        console.log("--- Phase 2: First Harvest (Funds Allocation) ---");
        vm.startPrank(management);

        // ✅ CORRETTO - usa il mock
        console.log(
            "Mock data before harvest:",
            mRSM.deposited(address(strategy3rd))
        );

        strategy3rd.harvest();

        // ✅ CORRETTO - verifica dopo l'harvest
        console.log(
            "Mock data after harvest:",
            mRSM.deposited(address(strategy3rd))
        );

        vm.stopPrank();

        //assertEq(WMNT.balanceOf(address(strategy3rd)), 0, "Strategy liquid want should be 0 after investment");

        // --- FASE 3: PRIMO PERIODO DI INTERESSI (60 giorni) ---
        console.log("--- Phase 3: First 60-Day Interest Period ---");
        uint256 pps_before_interest_period1 = vault.pricePerShare();
        skip(60 days);
     

        // --- FASE 4: SECONDO HARVEST (Report Primo Profitto) ---
        console.log("--- Phase 4: Second Harvest (Report 1st Profit) ---");
        vm.startPrank(management);
        strategy3rd.harvest();
        vm.stopPrank();
        
        uint256 pps_after_profit_report1 = vault.pricePerShare();
        console.log("PPS immediately after 2nd harvest (profit locked): %s", pps_after_profit_report1);
        assertApproxEqAbs(pps_after_profit_report1, pps_before_interest_period1, 2, "PPS should not change much before profit unlock");


        // --- FASE 5: SBLOCCO PRIMO PROFITTO (10 ore) ---
        console.log("--- Phase 5: Unlocking 1st Profit ---");
        skip(10 hours);
        uint256 pps_after_profit_unlock1 = vault.pricePerShare();
        console.log("PPS after 1st profit unlock: %s", pps_after_profit_unlock1);

        // --- FASE 6: SECONDO PERIODO DI INTERESSI (altri 60 giorni) ---
        console.log("--- Phase 6: Second 60-Day Interest Period ---");
        skip(60 days);

        console.log("====== Detailed Interest Test for Strategy3rd COMPLETED ======");
    
    }
}
