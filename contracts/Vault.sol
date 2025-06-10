// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";

/// @title Vault Interface Definitions and Storage for Forked Yearn V2 Vault
/// @notice Defines constants, interfaces, and storage layout for the Vault contract.
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @dev Interface for ERC20 tokens with detailed metadata functions.
 */
interface IDetailedERC20 is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint256);
}

/**
 * @dev Interface representing a strategy interacting with the Vault.
 */
interface IStrategy {
    function want() external view returns (address);
    function vault() external view returns (address);
    function isActive() external view returns (bool);
    function delegatedAssets() external view returns (uint256);
    function estimatedTotalAssets() external view returns (uint256);
    function withdraw(uint256 _amount) external returns (uint256);
    function migrate(address _newStrategy) external;
    function emergencyExit() external view returns (bool);
}

/**
 * @dev Main Vault Contract
 */
contract StMNT is IERC20, ReentrancyGuard, EIP712("StakingContract", "0.4.6") {
    // ========================== Constants ===============================

    /// @notice Version identifier of the Vault API
    string public constant API_VERSION = "0.4.6";

    // ========================== ERC20 Standard Storage ==================

    /// @notice Name of the Vault's token
    string public name;

    /// @notice Symbol of the Vault's token
    string public symbol;

    /// @notice Number of decimals used by the Vault's token
    uint8 public decimals;

    /// @notice Mapping of address to balance
    mapping(address => uint256) public override balanceOf;

    /// @notice Mapping of owner to spender to allowance
    mapping(address => mapping(address => uint256)) public override allowance;

    /// @notice Total token supply
    uint256 public override totalSupply;

    // ========================== Vault-Specific Storage ==================

    /// @notice Underlying ERC20 token the Vault manages
    IERC20 public token;

    /// @notice Address of the governance account
    address public governance;

    /// @notice Address of the management account
    address public management;

    /// @notice Address of the guardian account
    address public guardian;

    /// @notice Address pending to become governance
    address public pendingGovernance;

    /**
     * @dev Parameters tracking a specific Strategy's accounting within the Vault.
     */
    struct StrategyParams {
        uint256 performanceFee; // Strategist's fee (basis points)
        uint256 activation; // Timestamp of strategy activation
        uint256 debtRatio; // Maximum borrow amount (BPS of total assets)
        uint256 minDebtPerHarvest; // Minimum debt increase between harvests
        uint256 maxDebtPerHarvest; // Maximum debt increase between harvests
        uint256 lastReport; // Last report timestamp
        uint256 totalDebt; // Total outstanding debt
        uint256 totalGain; // Total profit realized by strategy
        uint256 totalLoss; // Total loss realized by strategy
    }

    // ============================= Vault Specific Events =============================

    /// @notice Emitted when tokens are deposited into the Vault
    event Deposit(address indexed recipient, uint256 shares, uint256 amount);

    /// @notice Emitted when tokens are withdrawn from the Vault
    event Withdraw(address indexed recipient, uint256 shares, uint256 amount);

    /// @notice Emitted when stray tokens are swept from the Vault
    event Sweep(address indexed token, uint256 amount);

    /// @notice Emitted when the locked profit degradation rate is updated
    event LockedProfitDegradationUpdated(uint256 value);

    /// @notice Emitted when a new Strategy is added to the Vault
    event StrategyAdded(
        address indexed strategy,
        uint256 debtRatio,
        uint256 minDebtPerHarvest,
        uint256 maxDebtPerHarvest,
        uint256 performanceFee
    );

    /// @notice Emitted when a Strategy reports gains, losses, or debt changes
    event StrategyReported(
        address indexed strategy,
        uint256 gain,
        uint256 loss,
        uint256 debtPaid,
        uint256 totalGain,
        uint256 totalLoss,
        uint256 totalDebt,
        uint256 debtAdded,
        uint256 debtRatio
    );

    /// @notice Emitted when fees are reported after a harvest
    event FeeReport(
        uint256 managementFee,
        uint256 performanceFee,
        uint256 strategistFee,
        uint256 duration
    );

    /// @notice Emitted when a withdrawal from a Strategy occurs
    event WithdrawFromStrategy(
        address indexed strategy,
        uint256 totalDebt,
        uint256 loss
    );

    // ============================= Governance and Management Events =============================

    /// @notice Emitted when the active governance is updated
    event UpdateGovernance(address governance);

    /// @notice Emitted when the management address is updated
    event UpdateManagement(address management);

    /// @notice Emitted when the rewards address is updated
    event UpdateRewards(address rewards);

    /// @notice Emitted when the deposit limit is updated
    event UpdateDepositLimit(uint256 depositLimit);

    /// @notice Emitted when the performance fee is updated
    event UpdatePerformanceFee(uint256 performanceFee);

    /// @notice Emitted when the management fee is updated
    event UpdateManagementFee(uint256 managementFee);

    /// @notice Emitted when the guardian address is updated
    event UpdateGuardian(address guardian);

    /// @notice Emitted when emergency shutdown status changes
    event EmergencyShutdown(bool active);

    /// @notice Emitted when the withdrawal queue is updated
    event UpdateWithdrawalQueue(address[20] queue);

    // ============================= Strategy Management Events =============================

    /// @notice Emitted when a Strategy's debt ratio is updated
    event StrategyUpdateDebtRatio(address indexed strategy, uint256 debtRatio);

    /// @notice Emitted when a Strategy's minimum debt per harvest is updated
    event StrategyUpdateMinDebtPerHarvest(
        address indexed strategy,
        uint256 minDebtPerHarvest
    );

    /// @notice Emitted when a Strategy's maximum debt per harvest is updated
    event StrategyUpdateMaxDebtPerHarvest(
        address indexed strategy,
        uint256 maxDebtPerHarvest
    );

    /// @notice Emitted when a Strategy's performance fee is updated
    event StrategyUpdatePerformanceFee(
        address indexed strategy,
        uint256 performanceFee
    );

    /// @notice Emitted when a Strategy migration occurs
    event StrategyMigrated(
        address indexed oldVersion,
        address indexed newVersion
    );

    /// @notice Emitted when a Strategy is revoked from use
    event StrategyRevoked(address indexed strategy);

    /// @notice Emitted when a Strategy is removed from the withdrawal queue
    event StrategyRemovedFromQueue(address indexed strategy);

    /// @notice Emitted when a Strategy is added to the withdrawal queue
    event StrategyAddedToQueue(address indexed strategy);

    /// @notice Emitted when a new pending governance address is set
    event NewPendingGovernance(address indexed pendingGovernance);

    /**
     * @dev Throws if called by any account other than governance.
     */
    modifier onlyGovernance() {
        require(msg.sender == governance, "Vault: !governance");
        _;
    }

    /// @notice Maximum number of strategies supported in the withdrawal queue
    uint256 public constant MAXIMUM_STRATEGIES = 20;

    /// @notice Scaling coefficient for locked profit degradation (100% = 1e18)
    uint256 public constant DEGRADATION_COEFFICIENT = 1e18;

    /// @notice Mapping from strategy address to its associated parameters
    mapping(address => StrategyParams) public strategies;

    /// @notice Withdrawal queue ordered by priority, first ZERO address encountered stops iteration
    address[MAXIMUM_STRATEGIES] public withdrawalQueue;

    /// @notice Whether the Vault is in emergency shutdown mode
    bool public emergencyShutdown;

    /// @notice Limit on the total assets the Vault can hold
    uint256 public depositLimit;

    /// @notice Maximum allowed total debt ratio across all strategies (in basis points)
    uint256 public debtRatio;

    /// @notice Amount of tokens currently idle inside the Vault
    uint256 public totalIdle;

    /// @notice Total amount of tokens borrowed by all strategies
    uint256 public totalDebt;

    /// @notice Timestamp of the last report across all strategies
    uint256 public lastReport;

    /// @notice Timestamp of Vault deployment (activation time)
    uint256 public activation;

    /// @notice Amount of profit currently locked and not withdrawable
    uint256 public lockedProfit;

    /// @notice Rate of locked profit degradation per block
    uint256 public lockedProfitDegradation;

    /// @notice Address receiving governance rewards
    address public rewards;

    /// @notice Management fee percentage (in basis points) charged by the Vault
    uint256 public managementFee;

    /// @notice Performance fee percentage (in basis points) charged by the Vault
    uint256 public performanceFee;

    /// @notice Basis points maximum value (100%)
    uint256 public constant MAX_BPS = 10_000;

    /// @notice Number of seconds in a year, based on 365.2425 days
    uint256 public constant SECS_PER_YEAR = 31_556_952;

    /// @notice Mapping of user address to nonce for permit signature approvals
    mapping(address => uint256) public nonces;

    /// @notice EIP712 domain separator type hash
    bytes32 public constant DOMAIN_TYPE_HASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );

    /// @notice EIP712 permit type hash for ERC20 approvals via signatures
    bytes32 public constant PERMIT_TYPE_HASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    constructor(
        address _token,
        address _governance,
        address _rewards,
        string memory _nameOverride,
        string memory _symbolOverride,
        address _guardian,
        address _management
    ) {
        initialize(
            _token,
            _governance,
            _rewards,
            _nameOverride,
            _symbolOverride,
            _guardian,
            _management
        );
    }

    /**
     * @notice Initializes the Vault. Can only be called once.
     * @dev Sets token, governance, management, rewards, and guardian addresses.
     * Also initializes fees and metadata (name, symbol).
     * Management and guardian default to msg.sender if not specified.
     * Name and symbol default to derived from token if overrides are empty.
     * Requirements:
     * - activation must be zero (vault not initialized).
     * @param _token Address of the ERC20 token the vault will manage.
     * @param _governance Address with governance rights.
     * @param _rewards Address where rewards are distributed.
     * @param _nameOverride Optional custom name for the Vault.
     * @param _symbolOverride Optional custom symbol for the Vault.
     * @param _guardian Guardian address. Defaults to msg.sender if zero.
     * @param _management Management address. Defaults to msg.sender if zero.
     */
    function initialize(
        address _token,
        address _governance,
        address _rewards,
        string memory _nameOverride,
        string memory _symbolOverride,
        address _guardian,
        address _management
    ) internal {
        require(activation == 0, "Vault: already initialized");

        token = IERC20(_token);

        if (bytes(_nameOverride).length == 0) {
            name = string(string.concat("st", IDetailedERC20(_token).name()));
        } else {
            name = _nameOverride;
        }

        if (bytes(_symbolOverride).length == 0) {
            symbol = string(
                string.concat("st", IDetailedERC20(_token).symbol())
            );
        } else {
            symbol = _symbolOverride;
        }

        uint256 _decimals = IDetailedERC20(_token).decimals();
        require(_decimals == 18, "Vault: token must have 18 decimals");
        decimals = uint8(_decimals);

        governance = _governance;
        emit UpdateGovernance(_governance);

        management = _management != address(0) ? _management : msg.sender;
        emit UpdateManagement(management);

        rewards = _rewards;
        emit UpdateRewards(_rewards);

        guardian = _guardian != address(0) ? _guardian : msg.sender;
        emit UpdateGuardian(guardian);

        performanceFee = 1_000; // 10% performance fee
        emit UpdatePerformanceFee(performanceFee);

        managementFee = 200; // 2% management fee
        emit UpdateManagementFee(managementFee);

        lastReport = block.timestamp;
        activation = block.timestamp;

        // Locked profit degrades over approx 6 hours
        lockedProfitDegradation = (DEGRADATION_COEFFICIENT * 46) / 1_000_000;
    }

    /**
     * @notice Returns the API version of this contract.
     * @dev Used to track which Vault version is deployed.
     * return The current API_VERSION string.
     */
    function apiVersion() external pure returns (string memory) {
        return API_VERSION;
    }

    /**
     * @notice Exposes the domain separator publicly.
     * return The domain separator as bytes32.
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @notice Allows governance to update the Vault's name.
     * @dev Only callable by the governance address.
     * @param _name The new name to set.
     */
    function setName(string calldata _name) external {
        require(msg.sender == governance, "Vault: !governance");
        name = _name;
    }

    /**
     * @notice Allows governance to update the Vault's symbol.
     * @dev Only callable by governance.
     * @param _symbol The new symbol to set.
     */
    function setSymbol(string calldata _symbol) external {
        require(msg.sender == governance, "Vault: !governance");
        symbol = _symbol;
    }

    /**
     * @notice Nominate a new address to become the governance.
     * @dev This sets a pending governance address, must be accepted separately.
     * Only callable by current governance.
     * @param _governance Address requested to take over governance.
     */
    function setGovernance(address _governance) external {
        require(msg.sender == governance, "Vault: !governance");
        emit NewPendingGovernance(_governance);
        pendingGovernance = _governance;
    }

    /**
     * @notice Accept governance responsibilities.
     * @dev Callable only by the pending governance address.
     * Updates the governance address to msg.sender.
     */
    function acceptGovernance() external {
        require(msg.sender == pendingGovernance, "Vault: !pending governance");
        governance = msg.sender;
        emit UpdateGovernance(msg.sender);
    }

    /**
     * @notice Changes the management address.
     * @dev Only callable by governance.
     * @param _management The address to set as management.
     */
    function setManagement(address _management) external onlyGovernance {
        management = _management;
        emit UpdateManagement(_management);
    }

    /**
     * @notice Changes the rewards address.
     * @dev Only callable by governance.
     * Requirements:
     * - New rewards address cannot be the Vault itself or the zero address.
     * @param _rewards The address to receive rewards.
     */
    function setRewards(address _rewards) external onlyGovernance {
        require(
            _rewards != address(0) && _rewards != address(this),
            "Vault: invalid rewards address"
        );
        rewards = _rewards;
        emit UpdateRewards(_rewards);
    }

    /**
     * @notice Changes the locked profit degradation rate.
     * @dev Only callable by governance.
     * @param _degradation The new degradation rate, scaled to 1e18.
     */
    function setLockedProfitDegradation(
        uint256 _degradation
    ) external onlyGovernance {
        require(
            _degradation <= DEGRADATION_COEFFICIENT,
            "Vault: degradation too high"
        );
        lockedProfitDegradation = _degradation;
        emit LockedProfitDegradationUpdated(_degradation);
    }

    /**
     * @notice Changes the maximum total amount of tokens that can be deposited into the Vault.
     * @dev Only callable by governance.
     * @param _limit The new deposit limit.
     */
    function setDepositLimit(uint256 _limit) external onlyGovernance {
        depositLimit = _limit;
        emit UpdateDepositLimit(_limit);
    }

    /**
     * @notice Changes the performance fee charged by the Vault.
     * @dev Only callable by governance.
     * Requirements:
     * - Fee must be less than or equal to 50% (MAX_BPS / 2).
     * @param _fee The new performance fee in basis points.
     */
    function setPerformanceFee(uint256 _fee) external onlyGovernance {
        require(_fee <= MAX_BPS / 2, "Vault: performance fee too high");
        performanceFee = _fee;
        emit UpdatePerformanceFee(_fee);
    }

    /**
     * @notice Changes the management fee charged by the Vault.
     * @dev Only callable by governance.
     * Requirements:
     * - Fee must be less than or equal to 100% (MAX_BPS).
     * @param _fee The new management fee in basis points.
     */
    function setManagementFee(uint256 _fee) external onlyGovernance {
        require(_fee <= MAX_BPS, "Vault: management fee too high");
        managementFee = _fee;
        emit UpdateManagementFee(_fee);
    }

    /**
     * @notice Changes the guardian address.
     * @dev Callable by current guardian or governance.
     * @param _guardian The new guardian address.
     */
    function setGuardian(address _guardian) external {
        require(
            msg.sender == guardian || msg.sender == governance,
            "Vault: !guardian or !governance"
        );
        guardian = _guardian;
        emit UpdateGuardian(_guardian);
    }

    /**
     * @notice Activates or deactivates emergency shutdown mode.
     * @dev
     * - If activating (true), callable by guardian or governance.
     * - If deactivating (false), only callable by governance.
     * @param _active Whether to activate (true) or deactivate (false) emergency mode.
     */
    function setEmergencyShutdown(bool _active) external {
        if (_active) {
            require(
                msg.sender == guardian || msg.sender == governance,
                "Vault: !guardian or !governance"
            );
        } else {
            require(
                msg.sender == governance,
                "Vault: only governance can disable shutdown"
            );
        }
        emergencyShutdown = _active;
        emit EmergencyShutdown(_active);
    }

    /**
     * @notice Updates the withdrawal queue with a new ordered list of strategies.
     * @dev
     * - Only callable by management or governance.
     * - Strategies must already exist in the current queue.
     * - No duplicates allowed.
     * - Zero address indicates end of queue.
     * @param _queue The new ordered queue of strategies.
     */
    function setWithdrawalQueue(
        address[MAXIMUM_STRATEGIES] calldata _queue
    ) external {
        require(
            msg.sender == management || msg.sender == governance,
            "Vault: !management or !governance"
        );

        address[MAXIMUM_STRATEGIES] memory oldQueue = withdrawalQueue;

        for (uint256 i = 0; i < MAXIMUM_STRATEGIES; ++i) {
            address newStrategy = _queue[i];

            if (newStrategy == address(0)) {
                require(
                    oldQueue[i] == address(0),
                    "Vault: cannot remove strategies"
                );
                break;
            }

            require(
                oldQueue[i] != address(0),
                "Vault: cannot add new strategies"
            );
            require(
                strategies[newStrategy].activation > 0,
                "Vault: strategy not active"
            );

            // Check that the new strategy exists in old queue and no duplicates
            bool existsInOldQueue = false;
            for (uint256 j = 0; j < MAXIMUM_STRATEGIES; ++j) {
                if (_queue[j] == address(0)) {
                    existsInOldQueue = true;
                    break;
                }
                if (newStrategy == oldQueue[j]) {
                    existsInOldQueue = true;
                }

                if (j <= i) {
                    // Only check for duplicates after current index
                    continue;
                }
                require(
                    newStrategy != _queue[j],
                    "Vault: duplicate strategies"
                );
            }

            require(existsInOldQueue, "Vault: new strategies not allowed");

            withdrawalQueue[i] = newStrategy;
        }

        emit UpdateWithdrawalQueue(_queue);
    }

    using SafeERC20 for IERC20;

    /**
     * @dev Safely transfers `amount` tokens from this contract to `receiver`.
     * @param _token Address of the ERC20 token.
     * @param _receiver Address receiving the tokens.
     * @param _amount Amount of tokens to transfer.
     */
    function _erc20SafeTransfer(
        address _token,
        address _receiver,
        uint256 _amount
    ) internal {
        IERC20(_token).safeTransfer(_receiver, _amount);
    }

    /**
     * @dev Safely transfers `amount` tokens from `sender` to `receiver`.
     * @param _token Address of the ERC20 token.
     * @param _sender Address sending the tokens.
     * @param _receiver Address receiving the tokens.
     * @param _amount Amount of tokens to transfer.
     */
    function _erc20SafeTransferFrom(
        address _token,
        address _sender,
        address _receiver,
        uint256 _amount
    ) internal {
        IERC20(_token).safeTransferFrom(_sender, _receiver, _amount);
    }

    /**
     * @dev Internal function to transfer Vault shares.
     * Reverts if trying to transfer to the Vault itself or to the zero address.
     * Emits a {Transfer} event.
     * @param _sender Address transferring the shares.
     * @param _receiver Address receiving the shares.
     * @param _amount Amount of shares to transfer.
     */
    function _transfer(
        address _sender,
        address _receiver,
        uint256 _amount
    ) internal {
        require(
            _receiver != address(0) && _receiver != address(this),
            "Vault: invalid receiver"
        );

        balanceOf[_sender] -= _amount;
        balanceOf[_receiver] += _amount;

        emit Transfer(_sender, _receiver, _amount);
    }

    /**
     * @notice Transfers shares from caller to `receiver`.
     * @dev Returns true on success.
     * @param _receiver Address receiving the shares.
     * @param _amount Amount of shares to transfer.
     * return True if the transfer succeeds.
     */
    function transfer(
        address _receiver,
        uint256 _amount
    ) external returns (bool) {
        _transfer(msg.sender, _receiver, _amount);
        return true;
    }
    /**
     * @notice Transfers `amount` shares from `sender` to `receiver`.
     * @dev If allowance is not MAX_UINT256, it decreases allowance.
     * @param _sender Address sending the shares.
     * @param _receiver Address receiving the shares.
     * @param _amount Amount of shares to transfer.
     * return True if transfer succeeds.
     */
    function transferFrom(
        address _sender,
        address _receiver,
        uint256 _amount
    ) external returns (bool) {
        if (allowance[_sender][msg.sender] != type(uint256).max) {
            allowance[_sender][msg.sender] -= _amount;
            emit Approval(_sender, msg.sender, allowance[_sender][msg.sender]);
        }
        _transfer(_sender, _receiver, _amount);
        return true;
    }

    /**
     * @notice Approves `spender` to spend `amount` tokens on behalf of caller.
     * @param _spender Address allowed to spend.
     * @param _amount Amount allowed.
     * return True if approval succeeds.
     */
    function approve(
        address _spender,
        uint256 _amount
    ) external returns (bool) {
        allowance[msg.sender][_spender] = _amount;
        emit Approval(msg.sender, _spender, _amount);
        return true;
    }

    /**
     * @notice Increases allowance for `spender` by `amount`.
     * @param _spender Address to increase allowance for.
     * @param _amount Amount to increase.
     * return True if approval succeeds.
     */
    function increaseAllowance(
        address _spender,
        uint256 _amount
    ) external returns (bool) {
        allowance[msg.sender][_spender] += _amount;
        emit Approval(msg.sender, _spender, allowance[msg.sender][_spender]);
        return true;
    }

    /**
     * @notice Decreases allowance for `spender` by `amount`.
     * @param _spender Address to decrease allowance for.
     * @param _amount Amount to decrease.
     * return True if approval succeeds.
     */
    function decreaseAllowance(
        address _spender,
        uint256 _amount
    ) external returns (bool) {
        allowance[msg.sender][_spender] -= _amount;
        emit Approval(msg.sender, _spender, allowance[msg.sender][_spender]);
        return true;
    }

    /**
     * @notice Approves spender via EIP-2612 Permit signature.
     * @param _owner Owner address.
     * @param _spender Spender address.
     * @param _amount Amount to approve.
     * @param _expiry Expiry timestamp.
     * @param _v Recovery byte of signature.
     * @param _r Half of signature.
     * @param _s Half of signature.
     * return True if permit succeeds.
     */
    function permit(
        address _owner,
        address _spender,
        uint256 _amount,
        uint256 _expiry,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external returns (bool) {
        require(_owner != address(0), "Vault: invalid owner");
        require(_expiry >= block.timestamp, "Vault: expired permit");

        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPE_HASH,
                _owner,
                _spender,
                _amount,
                nonces[_owner],
                _expiry
            )
        );

        bytes32 hash_ = _hashTypedDataV4(structHash);
        address signer_ = ECDSA.recover(hash_, _v, _r, _s);

        require(signer_ == _owner, "Vault: invalid signature");

        nonces[_owner] += 1;
        allowance[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
        return true;
    }

    /**
     * @notice Returns the total amount of assets under management by the Vault.
     * return Total assets (idle + debt).
     */
    function totalAssets() external view returns (uint256) {
        return _totalAssets();
    }

    /**
     * @dev Internal: Computes total assets (idle + debt).
     * return The total assets.
     */
    function _totalAssets() internal view returns (uint256) {
        return totalIdle + totalDebt;
    }

    /**
     * @dev Internal: Calculates the amount of locked profit based on degradation.
     * return Amount of currently locked profit.
     */
    function _calculateLockedProfit() internal view returns (uint256) {
        uint256 lockedFundsRatio = (block.timestamp - lastReport) *
            lockedProfitDegradation;

        if (lockedFundsRatio < DEGRADATION_COEFFICIENT) {
            uint256 _lockedProfit = lockedProfit;
            return
                _lockedProfit -
                ((lockedFundsRatio * _lockedProfit) / DEGRADATION_COEFFICIENT);
        } else {
            return 0;
        }
    }

    /**
     * @dev Internal: Returns the amount of free funds available.
     * return Amount of free funds.
     */
    function _freeFunds() internal view returns (uint256) {
        return _totalAssets() - _calculateLockedProfit();
    }

    /**
     * @dev Issues Vault shares for a given amount of underlying tokens.
     * @param _to Address receiving the new shares.
     * @param _amount Amount of underlying tokens deposited.
     * @return shares of Vault shares minted.
     */
    function _issueSharesForAmount(
        address _to,
        uint256 _amount
    ) internal returns (uint256 shares) {
        uint256 _totalSupply = totalSupply;

        if (_totalSupply > 0) {
            shares = (_amount * _totalSupply) / _freeFunds();
        } else {
            shares = _amount;
        }

        require(shares != 0, "Vault: zero shares");

        totalSupply = _totalSupply + shares;
        balanceOf[_to] += shares;

        emit Transfer(address(0), _to, shares);

        return shares;
    }
    using SafeERC20 for IERC20;

    /**
     * @notice Deposit `_amount` of tokens, minting Vault shares to `recipient`.
     * @dev If `_amount` is MAX_UINT256, deposits the entire balance.
     * @param _amount Amount of tokens to deposit.
     * @param _recipient Address receiving the Vault shares.
     * @return shares of Vault shares minted.
     */
    function deposit(
        uint256 _amount,
        address _recipient
    ) external nonReentrant returns (uint256 shares) {
        require(!emergencyShutdown, "Vault: deposits disabled");
        require(
            _recipient != address(0) && _recipient != address(this),
            "Vault: invalid recipient"
        );

        uint256 amount = _amount;

        if (amount == type(uint256).max) {
            amount = _min(
                depositLimit - _totalAssets(),
                token.balanceOf(msg.sender)
            );
        } else {
            require(
                _totalAssets() + amount <= depositLimit,
                "Vault: exceeds deposit limit"
            );
        }

        require(amount > 0, "Vault: deposit amount 0");

        shares = _issueSharesForAmount(_recipient, amount);

        token.safeTransferFrom(msg.sender, address(this), amount);
        totalIdle += amount;

        emit Deposit(_recipient, shares, amount);

        return shares;
    }

    /**
     * @dev Internal: Calculates value of given shares.
     * @param _shares Number of Vault shares.
     * return Value in underlying tokens.
     */
    function _shareValue(uint256 _shares) internal view returns (uint256) {
        if (totalSupply == 0) return _shares;
        return (_shares * _freeFunds()) / totalSupply;
    }

    /**u
     * @dev Internal: Calculates how many shares correspond to given amount of tokens.
     * @param _amount Amount of underlying tokens.
     * @return _number of Vault shares.
     */
    function _sharesForAmount(
        uint256 _amount
    ) internal view returns (uint256 _number) {
        uint256 _free = _freeFunds();
        if (_free > 0) {
            return _number = (_amount * totalSupply) / _free;
        } else {
            return _number = 0;
        }
    }

    /**
     * @notice Returns the maximum available shares for withdrawal.
     * @return shares shares available.
     */
    function maxAvailableShares() external view returns (uint256 shares) {
        shares = _sharesForAmount(totalIdle);

        for (uint256 i = 0; i < MAXIMUM_STRATEGIES; ++i) {
            address strategy = withdrawalQueue[i];
            if (strategy == address(0)) break;
            shares += _sharesForAmount(strategies[strategy].totalDebt);
        }

        return shares;
    }

    /**
     * @dev Internal: Reports loss for a strategy, adjusting debt ratios.
     * @param _strategy Strategy address.
     * @param _loss Amount of loss.
     */
    function _reportLoss(address _strategy, uint256 _loss) internal {
        uint256 totalDebtStrategy = strategies[_strategy].totalDebt;
        require(totalDebtStrategy >= _loss, "Vault: loss exceeds debt");

        if (debtRatio != 0) {
            uint256 ratioChange = _min(
                (_loss * debtRatio) / totalDebt,
                strategies[_strategy].debtRatio
            );
            strategies[_strategy].debtRatio -= ratioChange;
            debtRatio -= ratioChange;
        }

        strategies[_strategy].totalLoss += _loss;
        strategies[_strategy].totalDebt = totalDebtStrategy - _loss;
        totalDebt -= _loss;
    }

    /**
     * @notice Withdraws shares and redeems underlying tokens to `recipient`.
     * @param _maxShares Maximum number of shares to redeem.
     * @param _recipient Address receiving the withdrawn tokens.
     * @param _maxLoss Maximum acceptable loss in basis points.
     */
    function withdraw(
        uint256 _maxShares,
        address _recipient,
        uint256 _maxLoss
    ) external nonReentrant returns (uint256) {
        uint256 shares = _maxShares;

        require(_maxLoss <= MAX_BPS, "Vault: max loss too high");

        if (shares == type(uint256).max) {
            shares = balanceOf[msg.sender];
        }

        require(shares <= balanceOf[msg.sender], "Vault: exceeds balance");
        require(shares > 0, "Vault: 0 shares");

        uint256 value = _shareValue(shares);
        uint256 vaultBalance = totalIdle;

        if (value > vaultBalance) {
            uint256 totalLoss = 0;

            for (uint256 i = 0; i < MAXIMUM_STRATEGIES; ++i) {
                address strategy = withdrawalQueue[i];
                if (strategy == address(0)) break;
                if (value <= vaultBalance) break;

                uint256 amountNeeded = value - vaultBalance;
                amountNeeded = _min(
                    amountNeeded,
                    strategies[strategy].totalDebt
                );
                if (amountNeeded == 0) continue;

                uint256 preBalance = token.balanceOf(address(this));
                uint256 loss = IStrategy(strategy).withdraw(amountNeeded);
                uint256 withdrawn = token.balanceOf(address(this)) - preBalance;

                vaultBalance += withdrawn;
                if (loss > 0) {
                    value -= loss;
                    totalLoss += loss;
                    _reportLoss(strategy, loss);
                }

                uint256 debtRepayment = _min(
                    withdrawn,
                    strategies[strategy].totalDebt
                );
                strategies[strategy].totalDebt -= debtRepayment;
                totalDebt -= debtRepayment;

                /*
                strategies[strategy].totalDebt -= withdrawn;
                totalDebt -= withdrawn;
                */

                emit WithdrawFromStrategy(
                    strategy,
                    strategies[strategy].totalDebt,
                    loss
                );
            }

            totalIdle = vaultBalance;

            if (value > vaultBalance) {
                value = vaultBalance;
                shares = _sharesForAmount(value + totalLoss);
            }

            require(
                totalLoss <= (_maxLoss * (value + totalLoss)) / MAX_BPS,
                "Vault: loss too high"
            );
        }

        totalSupply -= shares;
        balanceOf[msg.sender] -= shares;
        emit Transfer(msg.sender, address(0), shares);

        totalIdle -= value;
        token.safeTransfer(_recipient, value);
        emit Withdraw(_recipient, shares, value);

        return value;
    }

    /**
     * @dev Internal: Returns the minimum of two numbers.
     */
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
    /**
     * @notice Returns the price of a single Vault share.
     * @return Price per share.
     */
    function pricePerShare() external view returns (uint256 Price) {
        return Price = _shareValue(10 ** uint256(decimals));
    }

    /**
     * @dev Internal: Organizes withdrawal queue removing gaps.
     */
    function _organizeWithdrawalQueue() internal {
        uint256 offset = 0;
        for (uint256 i = 0; i < MAXIMUM_STRATEGIES; ++i) {
            address strategy = withdrawalQueue[i];
            if (strategy == address(0)) {
                offset++;
            } else if (offset > 0) {
                withdrawalQueue[i - offset] = strategy;
                withdrawalQueue[i] = address(0);
            }
        }
    }

    /**
     * @notice Adds a new strategy to the Vault.
     */
    function addStrategy(
        address _strategy,
        uint256 _debtRatio,
        uint256 _minDebtPerHarvest,
        uint256 _maxDebtPerHarvest,
        uint256 _performanceFee
    ) external onlyGovernance {
        require(
            withdrawalQueue[MAXIMUM_STRATEGIES - 1] == address(0),
            "Vault: queue full"
        );
        require(!emergencyShutdown, "Vault: emergency shutdown");
        require(_strategy != address(0), "Vault: invalid strategy");
        require(strategies[_strategy].activation == 0, "Vault: already added");
        require(
            IStrategy(_strategy).vault() == address(this),
            "Vault: wrong vault"
        );
        require(
            IStrategy(_strategy).want() == address(token),
            "Vault: wrong want token"
        );
        require(debtRatio + _debtRatio <= MAX_BPS, "Vault: debtRatio overflow");
        require(
            _minDebtPerHarvest <= _maxDebtPerHarvest,
            "Vault: minDebt > maxDebt"
        );
        require(_performanceFee <= MAX_BPS / 2, "Vault: fee too high");

        strategies[_strategy] = StrategyParams({
            performanceFee: _performanceFee,
            activation: block.timestamp,
            debtRatio: _debtRatio,
            minDebtPerHarvest: _minDebtPerHarvest,
            maxDebtPerHarvest: _maxDebtPerHarvest,
            lastReport: block.timestamp,
            totalDebt: 0,
            totalGain: 0,
            totalLoss: 0
        });

        debtRatio += _debtRatio;

        withdrawalQueue[MAXIMUM_STRATEGIES - 1] = _strategy;
        _organizeWithdrawalQueue();

        emit StrategyAdded(
            _strategy,
            _debtRatio,
            _minDebtPerHarvest,
            _maxDebtPerHarvest,
            _performanceFee
        );
    }

    /**
     * @notice Updates the debt ratio of a strategy.
     */
    function updateStrategyDebtRatio(
        address _strategy,
        uint256 _debtRatio
    ) external {
        require(
            msg.sender == management || msg.sender == governance,
            "Vault: !authorized"
        );
        require(strategies[_strategy].activation > 0, "Vault: not active");
        require(
            !IStrategy(_strategy).emergencyExit(),
            "Vault: strategy emergency exit"
        );

        debtRatio -= strategies[_strategy].debtRatio;
        strategies[_strategy].debtRatio = _debtRatio;
        debtRatio += _debtRatio;


        require(debtRatio <= MAX_BPS, "Vault: debtRatio overflow");

        emit StrategyUpdateDebtRatio(_strategy, _debtRatio);
    }

    /**
     * @notice Updates minDebtPerHarvest for a strategy.
     */
    function updateStrategyMinDebtPerHarvest(
        address _strategy,
        uint256 _minDebtPerHarvest
    ) external {
        require(
            msg.sender == management || msg.sender == governance,
            "Vault: !authorized"
        );
        require(strategies[_strategy].activation > 0, "Vault: not active");
        require(
            strategies[_strategy].maxDebtPerHarvest >= _minDebtPerHarvest,
            "Vault: invalid min"
        );

        strategies[_strategy].minDebtPerHarvest = _minDebtPerHarvest;

        emit StrategyUpdateMinDebtPerHarvest(_strategy, _minDebtPerHarvest);
    }

    /**
     * @notice Updates maxDebtPerHarvest for a strategy.
     */
    function updateStrategyMaxDebtPerHarvest(
        address _strategy,
        uint256 _maxDebtPerHarvest
    ) external {
        require(
            msg.sender == management || msg.sender == governance,
            "Vault: !authorized"
        );
        require(strategies[_strategy].activation > 0, "Vault: not active");
        require(
            strategies[_strategy].minDebtPerHarvest <= _maxDebtPerHarvest,
            "Vault: invalid max"
        );

        strategies[_strategy].maxDebtPerHarvest = _maxDebtPerHarvest;

        emit StrategyUpdateMaxDebtPerHarvest(_strategy, _maxDebtPerHarvest);
    }

    /**
     * @notice Updates the performance fee for a strategy.
     */
    function updateStrategyPerformanceFee(
        address _strategy,
        uint256 _performanceFee
    ) external onlyGovernance {
        require(_performanceFee <= MAX_BPS / 2, "Vault: fee too high");
        require(strategies[_strategy].activation > 0, "Vault: not active");

        strategies[_strategy].performanceFee = _performanceFee;

        emit StrategyUpdatePerformanceFee(_strategy, _performanceFee);
    }

    /**
     * @dev Internal: Revokes a strategy, setting its debt ratio to 0.
     */
    function _revokeStrategy(address _strategy) internal {
        debtRatio -= strategies[_strategy].debtRatio;
        strategies[_strategy].debtRatio = 0;
        emit StrategyRevoked(_strategy);
    }

    /**
     * @notice Migrates assets from an old strategy to a new one.
     */
    function migrateStrategy(
        address _oldVersion,
        address _newVersion
    ) external onlyGovernance {
        require(_newVersion != address(0), "Vault: invalid new strategy");
        require(
            strategies[_oldVersion].activation > 0,
            "Vault: old not active"
        );
        require(
            strategies[_newVersion].activation == 0,
            "Vault: new already active"
        );

        StrategyParams memory old = strategies[_oldVersion];

        _revokeStrategy(_oldVersion);

        debtRatio += old.debtRatio;
        strategies[_oldVersion].totalDebt = 0;

        strategies[_newVersion] = StrategyParams({
            performanceFee: old.performanceFee,
            activation: old.lastReport,
            debtRatio: old.debtRatio,
            minDebtPerHarvest: old.minDebtPerHarvest,
            maxDebtPerHarvest: old.maxDebtPerHarvest,
            lastReport: old.lastReport,
            totalDebt: old.totalDebt,
            totalGain: 0,
            totalLoss: 0
        });

        IStrategy(_oldVersion).migrate(_newVersion);

        emit StrategyMigrated(_oldVersion, _newVersion);

        for (uint256 i = 0; i < MAXIMUM_STRATEGIES; ++i) {
            if (withdrawalQueue[i] == _oldVersion) {
                withdrawalQueue[i] = _newVersion;
                break;
            }
        }
    }

    /**
     * @notice Revokes a strategy, callable by governance, guardian, or the strategy itself.
     */
    function revokeStrategy(address _strategy) external {
        console.log("Sono qui dentro il revokeStrategy");
        require(
            msg.sender == _strategy ||
                msg.sender == governance ||
                msg.sender == guardian,
            "Vault: !authorized"
        );
        require(strategies[_strategy].debtRatio != 0, "Vault: already revoked");
        _revokeStrategy(_strategy);
    }
    /**
     * @notice Adds a strategy to the withdrawal queue.
     */
    function addStrategyToQueue(address _strategy) external {
        require(
            msg.sender == management || msg.sender == governance,
            "Vault: !authorized"
        );
        require(strategies[_strategy].activation > 0, "Vault: not active");

        uint256 lastIdx = 0;
        for (uint256 i = 0; i < MAXIMUM_STRATEGIES; ++i) {
            address s = withdrawalQueue[i];
            if (s == address(0)) break;
            require(s != _strategy, "Vault: already in queue");
            lastIdx++;
        }
        require(lastIdx < MAXIMUM_STRATEGIES, "Vault: queue full");

        withdrawalQueue[MAXIMUM_STRATEGIES - 1] = _strategy;
        _organizeWithdrawalQueue();

        emit StrategyAddedToQueue(_strategy);
    }

    /**
     * @notice Removes a strategy from the withdrawal queue.
     */
    function removeStrategyFromQueue(address _strategy) external {
        require(
            msg.sender == management || msg.sender == governance,
            "Vault: !authorized"
        );

        for (uint256 i = 0; i < MAXIMUM_STRATEGIES; ++i) {
            if (withdrawalQueue[i] == _strategy) {
                withdrawalQueue[i] = address(0);
                _organizeWithdrawalQueue();
                emit StrategyRemovedFromQueue(_strategy);
                return;
            }
        }
        revert("Vault: strategy not in queue");
    }

    /**
     * @dev Internal: Calculates debt outstanding for a strategy.
     */
    function _debtOutstanding(
        address _strategy
    ) internal view returns (uint256) {
        if (debtRatio == 0) {
            return strategies[_strategy].totalDebt;
        }

        uint256 strategyDebtLimit = (strategies[_strategy].debtRatio *
            _totalAssets()) / MAX_BPS;
        uint256 strategyTotalDebt = strategies[_strategy].totalDebt;

        if (emergencyShutdown) {
            return strategyTotalDebt;
        } else if (strategyTotalDebt <= strategyDebtLimit) {
            return 0;
        } else {
            return strategyTotalDebt - strategyDebtLimit;
        }
    }

    /**
     * @notice Returns debt outstanding for the caller strategy.
     */
    function debtOutstanding() external view returns (uint256) {
        return _debtOutstanding(msg.sender);
    }

    /**
     * @dev Internal: Calculates available credit for a strategy.
     */
    function _creditAvailable(
        address _strategy
    ) internal view returns (uint256) {
        if (emergencyShutdown) return 0;

        uint256 vaultAssets = _totalAssets();
        uint256 vaultDebtLimit = (debtRatio * vaultAssets) / MAX_BPS;
        uint256 vaultTotalDebt = totalDebt;

        uint256 strategyDebtLimit = (strategies[_strategy].debtRatio *
            vaultAssets) / MAX_BPS;
        uint256 strategyTotalDebt = strategies[_strategy].totalDebt;

        if (
            strategyDebtLimit <= strategyTotalDebt ||
            vaultDebtLimit <= vaultTotalDebt
        ) {
            return 0;
        }

        uint256 available = strategyDebtLimit - strategyTotalDebt;
        available = _min(available, vaultDebtLimit - vaultTotalDebt);
        available = _min(available, totalIdle);

        uint256 minDebt = strategies[_strategy].minDebtPerHarvest;
        uint256 maxDebt = strategies[_strategy].maxDebtPerHarvest;

        if (available < minDebt) {
            return 0;
        } else {
            return _min(available, maxDebt);
        }
    }

    /**
     * @notice Returns available credit for a strategy.
     */
    function creditAvailable(
        address _strategy
    ) external view returns (uint256) {
        return _creditAvailable(_strategy);
    }

    /**
     * @dev Internal: Calculates expected return of a strategy.
     */
    function _expectedReturn(
        address _strategy
    ) internal view returns (uint256) {
        uint256 _lastReport = strategies[_strategy].lastReport;
        uint256 timeSinceLast = block.timestamp - _lastReport;
        uint256 totalHarvestTime = _lastReport -
            strategies[_strategy].activation;

        if (
            timeSinceLast > 0 &&
            totalHarvestTime > 0 &&
            IStrategy(_strategy).isActive()
        ) {
            return
                (strategies[_strategy].totalGain * timeSinceLast) /
                totalHarvestTime;
        } else {
            return 0;
        }
    }

    /**
     * @notice Returns expected return for a strategy.
     */
    function expectedReturn(address _strategy) external view returns (uint256) {
        return _expectedReturn(_strategy);
    }

    /**
     * @notice Returns the available deposit limit.
     */
    function availableDepositLimit() external view returns (uint256) {
        uint256 totalAssetsVault = _totalAssets();
        if (depositLimit > totalAssetsVault) {
            return depositLimit - totalAssetsVault;
        } else {
            return 0;
        }
    }

    /**
     * @dev Internal: Assesses management, performance, and strategist fees.
     */
    function _assessFees(
        address _strategy,
        uint256 _gain
    ) internal returns (uint256) {
        if (strategies[_strategy].activation == block.timestamp) {
            return 0; // No fees on first activation
        }

        uint256 duration = block.timestamp - strategies[_strategy].lastReport;
        require(duration > 0, "Vault: duration is 0");

        if (_gain == 0) return 0;

        uint256 debt = strategies[_strategy].totalDebt;
        uint256 delegated = IStrategy(_strategy).delegatedAssets();
        uint256 managementFeeAmount = ((debt - delegated) *
            duration *
            managementFee) /
            MAX_BPS /
            SECS_PER_YEAR;

        uint256 strategistFee = (_gain * strategies[_strategy].performanceFee) /
            MAX_BPS;
        uint256 performanceFeeAmount = (_gain * performanceFee) / MAX_BPS;

        uint256 totalFee = managementFeeAmount +
            strategistFee +
            performanceFeeAmount;

        if (totalFee > _gain) {
            totalFee = _gain;
        }

        if (totalFee > 0) {
            uint256 rewardShares = _issueSharesForAmount(
                address(this),
                totalFee
            );

            if (strategistFee > 0) {
                uint256 strategistReward = (strategistFee * rewardShares) /
                    totalFee;
                _transfer(address(this), _strategy, strategistReward);
            }

            uint256 remaining = balanceOf[address(this)];
            if (remaining > 0) {
                _transfer(address(this), rewards, remaining);
            }
        }

        emit FeeReport(
            managementFeeAmount,
            performanceFeeAmount,
            strategistFee,
            duration
        );

        return totalFee;
    }

    /**
     * @notice Strategy reports gains, losses, and debt repayments to the Vault.
     * @param _gain Amount gained since last report.
     * @param _loss Amount lost since last report.
     * @param _debtPayment Debt payment made by the Strategy.
     * return Outstanding debt after the report.
     */
    function report(
        uint256 _gain,
        uint256 _loss,
        uint256 _debtPayment
    ) external nonReentrant returns (uint256) {
        StrategyParams storage params = strategies[msg.sender];
        require(params.activation > 0, "Vault: !approved strategy");
        //! Problema di arrotondamento
        if (_debtPayment == 1) {
            --_debtPayment;
        }
        // Sanity check balance
        //! Commenti per test
        if (token.balanceOf(msg.sender) < _gain + _debtPayment) {
            console.log("Vault: Insufficient balance in strategy");
            console.log("Required gain: ", _gain);
            console.log("Required debt payment: ", _debtPayment);
            console.log("Strategy balance: ", token.balanceOf(msg.sender));
        }
        require(
            token.balanceOf(msg.sender) >= _gain + _debtPayment,
            "Vault: insufficient balance"
        );

        if (_loss > 0) {
            _reportLoss(msg.sender, _loss);
        }

        uint256 totalFees = _assessFees(msg.sender, _gain);

        params.totalGain += _gain;

        uint256 credit = _creditAvailable(msg.sender);
        uint256 debt = _debtOutstanding(msg.sender);
        uint256 debtPayment = _min(_debtPayment, debt);

        if (debtPayment > 0) {
            params.totalDebt -= debtPayment;
            totalDebt -= debtPayment;
            debt -= debtPayment;
        }

        if (credit > 0) {
            params.totalDebt += credit;
            totalDebt += credit;
        }

        uint256 totalAvailable = _gain + debtPayment;

        if (totalAvailable < credit) {
            totalIdle -= (credit - totalAvailable);
            token.safeTransfer(msg.sender, credit - totalAvailable);
        } else if (totalAvailable > credit) {
            totalIdle += (totalAvailable - credit);
            token.safeTransferFrom(
                msg.sender,
                address(this),
                totalAvailable - credit
            );
        }

        uint256 lockedProfitBeforeLoss = _calculateLockedProfit() +
            _gain -
            totalFees;
        if (lockedProfitBeforeLoss > _loss) {
            lockedProfit = lockedProfitBeforeLoss - _loss;
        } else {
            lockedProfit = 0;
        }

        params.lastReport = block.timestamp;
        lastReport = block.timestamp;

        emit StrategyReported(
            msg.sender,
            _gain,
            _loss,
            debtPayment,
            params.totalGain,
            params.totalLoss,
            params.totalDebt,
            credit,
            params.debtRatio
        );

        if (params.debtRatio == 0 || emergencyShutdown) {
            return IStrategy(msg.sender).estimatedTotalAssets();
        } else {
            return debt;
        }
    }

    /**
     * @notice Sweep non-vault tokens mistakenly sent to the Vault.
     * @param _token Token to sweep.
     * @param _amount Amount to sweep, defaults to entire balance.
     */
    function sweep(address _token, uint256 _amount) external onlyGovernance {
        uint256 value = _amount;

        if (value == type(uint256).max) {
            value = IERC20(_token).balanceOf(address(this));
        }

        // Special handling for the vault's own token
        if (_token == address(token)) {
            require(
                token.balanceOf(address(this)) > totalIdle,
                "Vault: no excess vault token"
            );
            value = token.balanceOf(address(this)) - totalIdle;
        }

        emit Sweep(_token, value);
        IERC20(_token).safeTransfer(governance, value);
    }
}
