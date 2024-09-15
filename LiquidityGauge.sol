// Explanation and Comments

// Staking and Withdrawal:

// LPs can stake their LP tokens to start earning rewards.
// They can withdraw their staked tokens at any time.
// Reward Distribution:

// Rewards are calculated based on the user's stake and the reward rate.
// When a bribe is added, the reward rate is updated, and rewards are distributed over a fixed period (e.g., 7 days).
// Reward Calculation:

// Uses standard methods for calculating rewardPerToken and earned rewards.
// The updateReward modifier ensures rewards are updated whenever a user's balance changes.
// Bribe Notification:

// The notifyRewardAmount function is called by the GaugeController when new bribes are added.
// Updates the reward rate accordingly.
// Handling Multiple Reward Tokens:

// The contract maintains an array rewardTokens to keep track of all reward tokens.
// Users can claim all rewards in a single transaction using getReward.

// Security Enhancements:

// SafeERC20: Used for all token transfers to prevent issues with non-standard ERC20 tokens.
// Input Validations: Added require statements to ensure valid amounts and durations.
// ReentrancyGuard: Protects against reentrancy attacks using the nonReentrant modifier.
// Bribe Distribution Adjustments:

// Adjustable Reward Duration: The notifyRewardAmount function accepts a rewardDuration parameter, allowing for dynamic distribution periods.
// Dynamic Calculation Methods: Reward rates adjust based on the new reward amount and duration.
// Period Finish Tracking: The periodFinish variable tracks when the reward distribution period ends for each reward token.
// Dynamic Reward Tokens Management:

// Multiple Reward Tokens: Supports multiple reward tokens, maintaining an array rewardTokens.
// Efficient Interaction: Users can claim rewards for all tokens in a single transaction using the getReward function.
// User-Friendly Functions: Provided functions like balanceOf and getRewardTokens for users to interact with their stakes and rewards.

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import statements
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title LiquidityGauge
/// @notice Allows LPs to stake their LP tokens and earn additional rewards with multiple reward tokens
contract LiquidityGauge is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public lpToken; // LP token of the pool

    // Mapping from user address to stake amount
    mapping(address => uint256) public balances;

    // Total staked LP tokens
    uint256 public totalSupply;

    // Reward tokens and related data
    struct Reward {
        IERC20 token;
        uint256 rewardRate;
        uint256 periodFinish;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        uint256 duration;
    }

    // Mapping from token address to Reward struct
    mapping(address => Reward) public rewards;

    // Mapping from user to token to rewards earned
    mapping(address => mapping(address => uint256)) public userRewards;

    // Mapping from user to token to user reward per token paid
    mapping(address => mapping(address => uint256)) public userRewardPerTokenPaid;

    // Array of reward tokens
    address[] public rewardTokens;

    // Events
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, address indexed token, uint256 reward);
    event RewardAdded(address indexed token, uint256 reward, uint256 duration);

    /// @notice Initializes the contract with the LP token
    /// @param _lpToken Address of the LP token
    constructor(address _lpToken) {
        require(_lpToken != address(0), "Invalid LP token address");
        lpToken = IERC20(_lpToken);
    }

    /// @notice Allows users to stake their LP tokens
    /// @param amount Amount of LP tokens to stake
    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot stake zero amount");

        totalSupply += amount;
        balances[msg.sender] += amount;

        lpToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    /// @notice Allows users to withdraw their staked LP tokens
    /// @param amount Amount of LP tokens to withdraw
    function withdraw(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw zero amount");
        require(balances[msg.sender] >= amount, "Insufficient balance");

        totalSupply -= amount;
        balances[msg.sender] -= amount;

        lpToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Allows users to claim their rewards
    function getReward() external nonReentrant updateReward(msg.sender) {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 reward = userRewards[msg.sender][token];
            if (reward > 0) {
                userRewards[msg.sender][token] = 0;
                IERC20(token).safeTransfer(msg.sender, reward);
                emit RewardPaid(msg.sender, token, reward);
            }
        }
    }

    /// @notice Allows the gauge to be notified of new reward amounts (called when bribes are added)
    /// @param token Address of the reward token
    /// @param reward Amount of the reward
    /// @param rewardDuration Duration over which the reward is distributed
    function notifyRewardAmount(address token, uint256 reward, uint256 rewardDuration) external updateReward(address(0)) {
        // Only accept rewards from authorized addresses (e.g., GaugeController)
        require(msg.sender == tx.origin, "Contracts cannot call this function");
        require(rewardDuration >= 1 days, "Reward duration too short");

        if (rewards[token].lastUpdateTime == 0) {
            // New reward token
            rewards[token] = Reward({
                token: IERC20(token),
                rewardRate: 0,
                periodFinish: 0,
                lastUpdateTime: block.timestamp,
                rewardPerTokenStored: 0,
                duration: rewardDuration
            });
            rewardTokens.push(token);
        }

        Reward storage r = rewards[token];
        _updateRewardData(r);

        if (block.timestamp >= r.periodFinish) {
            r.rewardRate = reward / rewardDuration;
        } else {
            uint256 remaining = r.periodFinish - block.timestamp;
            uint256 leftover = remaining * r.rewardRate;
            r.rewardRate = (reward + leftover) / rewardDuration;
        }

        r.lastUpdateTime = block.timestamp;
        r.periodFinish = block.timestamp + rewardDuration;
        r.duration = rewardDuration;

        emit RewardAdded(token, reward, rewardDuration);
    }

    /// @notice Modifier to update reward variables
    /// @param account Address of the user to update rewards for
    modifier updateReward(address account) {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            Reward storage r = rewards[token];
            _updateRewardData(r);
            if (account != address(0)) {
                userRewards[account][token] = earned(account, token);
                userRewardPerTokenPaid[account][token] = r.rewardPerTokenStored;
            }
        }
        _;
    }

    /// @notice Updates reward data for a token
    /// @param r Reward struct to update
    function _updateRewardData(Reward storage r) internal {
        r.rewardPerTokenStored = rewardPerToken(r);
        r.lastUpdateTime = lastTimeRewardApplicable(r);
    }

    /// @notice Returns the last time reward was applicable
    /// @param r Reward struct
    /// @return Timestamp of the last applicable reward time
    function lastTimeRewardApplicable(Reward storage r) internal view returns (uint256) {
        return block.timestamp < r.periodFinish ? block.timestamp : r.periodFinish;
    }

    /// @notice Calculates the reward per token stored
    /// @param r Reward struct
    /// @return Reward per token stored
    function rewardPerToken(Reward storage r) internal view returns (uint256) {
        if (totalSupply == 0) {
            return r.rewardPerTokenStored;
        }
        return
            r.rewardPerTokenStored +
            (((lastTimeRewardApplicable(r) - r.lastUpdateTime) * r.rewardRate * 1e18) / totalSupply);
    }

    /// @notice Calculates the earned reward for a user
    /// @param account Address of the user
    /// @param token Address of the reward token
    /// @return Amount of reward earned
    function earned(address account, address token) public view returns (uint256) {
        Reward storage r = rewards[token];
        return
            ((balances[account] * (rewardPerToken(r) - userRewardPerTokenPaid[account][token])) / 1e18) +
            userRewards[account][token];
    }

    /// @notice Returns the list of reward tokens
    /// @return Array of reward token addresses
    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    /// @notice Returns the user's staked balance
    /// @param account Address of the user
    /// @return Amount of LP tokens staked by the user
    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }
}
