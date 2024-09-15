// Explanation and Comments

// Gauge Struct: Contains the pool address, gauge address, and the weight assigned through voting.

// Voting Mechanism:

// Users can vote on which pools should receive more incentives by locking their governance tokens.
// Votes are stored, and total weights per pool are updated accordingly.
// Tokens used for voting are locked in the controller.
// Bribe Functionality:

// External parties can add incentives (bribes) to a gauge by transferring ERC-20 tokens.
// The gauge contract handles the distribution of these tokens to LPs based on their stake and votes.
// Security Enhancements:

// SafeERC20: Used for all token transfers (safeTransferFrom, safeTransfer) to handle any non-standard ERC20 tokens.
// Input Validations: Added require statements to validate inputs such as pool indices, addresses, and amounts.
// Access Control: Only the contract owner can add new gauges using onlyOwner modifier from Ownable.
// Governance Improvements:

// Vote Locking Mechanism: Implemented voteUnlockTime mapping to track when users can withdraw or reallocate their votes.
// Withdraw Votes: Users can withdraw their locked governance tokens after the lock period via the withdrawVotes function.
// Reallocate Votes: Users can reallocate their votes to different pools using the reallocateVotes function. The vote lock period resets upon reallocation.
// Events: Added VotesReallocated event to track vote reallocations.
// Bribe Distribution Adjustments:

// Adjustable Reward Duration: The addBribe function accepts rewardDuration as a parameter, allowing bribes to be distributed over a variable time frame.
// Input Validations: Ensured that the reward duration is at least 1 day to prevent too short distribution periods.


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import statements
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title GaugeController
/// @notice Manages gauges and voting for incentive distribution with enhanced governance features
contract GaugeController is Ownable {
    using SafeERC20 for IERC20;

    struct Gauge {
        address poolAddress;
        address gaugeAddress;
        uint256 weight; // Total weight assigned through voting
    }

    // List of all gauges
    Gauge[] public gauges;

    // Mapping from user to pool index to vote weight
    mapping(address => mapping(uint256 => uint256)) public userVotes;

    // Total weight per pool
    mapping(uint256 => uint256) public totalWeights;

    // Governance token used for voting
    IERC20 public governanceToken;

    // Locking period for votes (e.g., 1 week)
    uint256 public constant VOTE_LOCK_PERIOD = 7 days;

    // Mapping from user to unlock time
    mapping(address => uint256) public voteUnlockTime;

    // Events
    event GaugeAdded(address indexed pool, address indexed gauge);
    event Voted(address indexed user, uint256 indexed poolIndex, uint256 weight);
    event VoteWithdrawn(address indexed user, uint256 weight);
    event VotesReallocated(address indexed user, uint256 oldPoolIndex, uint256 newPoolIndex, uint256 weight);
    event BribeAdded(address indexed token, uint256 amount, uint256 indexed poolIndex, uint256 rewardDuration);

    /// @notice Initializes the contract with the governance token address
    /// @param _governanceToken Address of the governance token
    constructor(address _governanceToken) {
        require(_governanceToken != address(0), "Invalid governance token address");
        governanceToken = IERC20(_governanceToken);
    }

    /// @notice Adds a new gauge for a pool
    /// @param poolAddress Address of the liquidity pool
    /// @param gaugeAddress Address of the gauge contract associated with the pool
    function addGauge(address poolAddress, address gaugeAddress) external onlyOwner {
        require(poolAddress != address(0), "Invalid pool address");
        require(gaugeAddress != address(0), "Invalid gauge address");

        gauges.push(Gauge({
            poolAddress: poolAddress,
            gaugeAddress: gaugeAddress,
            weight: 0
        }));
        emit GaugeAdded(poolAddress, gaugeAddress);
    }

    /// @notice Allows users to vote on gauge weights
    /// @param poolIndex Index of the pool to vote for
    /// @param weight Weight of the vote (amount of governance tokens)
    function vote(uint256 poolIndex, uint256 weight) external {
        require(poolIndex < gauges.length, "Invalid pool index");
        require(weight > 0, "Weight must be greater than zero");
        require(governanceToken.balanceOf(msg.sender) >= weight, "Insufficient governance tokens");

        // Transfer governance tokens to the controller (tokens are locked)
        governanceToken.safeTransferFrom(msg.sender, address(this), weight);

        // Update votes and total weights
        userVotes[msg.sender][poolIndex] += weight;
        totalWeights[poolIndex] += weight;
        gauges[poolIndex].weight += weight;

        // Set the vote unlock time
        voteUnlockTime[msg.sender] = block.timestamp + VOTE_LOCK_PERIOD;

        emit Voted(msg.sender, poolIndex, weight);
    }

    /// @notice Allows users to withdraw their votes after the lock period
    function withdrawVotes() external {
        require(block.timestamp >= voteUnlockTime[msg.sender], "Votes are still locked");

        uint256 totalUserWeight = 0;

        // Iterate over all gauges to calculate total weight and update weights
        for (uint256 i = 0; i < gauges.length; i++) {
            uint256 userWeight = userVotes[msg.sender][i];
            if (userWeight > 0) {
                userVotes[msg.sender][i] = 0;
                totalWeights[i] -= userWeight;
                gauges[i].weight -= userWeight;
                totalUserWeight += userWeight;
            }
        }

        require(totalUserWeight > 0, "No votes to withdraw");

        // Transfer governance tokens back to the user
        governanceToken.safeTransfer(msg.sender, totalUserWeight);

        emit VoteWithdrawn(msg.sender, totalUserWeight);
    }

    /// @notice Allows users to reallocate their votes to different pools
    /// @param oldPoolIndex Index of the pool to remove votes from
    /// @param newPoolIndex Index of the pool to assign votes to
    /// @param weight Amount of votes to reallocate
    function reallocateVotes(uint256 oldPoolIndex, uint256 newPoolIndex, uint256 weight) external {
        require(oldPoolIndex < gauges.length && newPoolIndex < gauges.length, "Invalid pool index");
        require(userVotes[msg.sender][oldPoolIndex] >= weight, "Insufficient votes to reallocate");

        // Ensure votes are not locked
        require(block.timestamp >= voteUnlockTime[msg.sender], "Votes are still locked");

        // Update vote weights
        userVotes[msg.sender][oldPoolIndex] -= weight;
        totalWeights[oldPoolIndex] -= weight;
        gauges[oldPoolIndex].weight -= weight;

        userVotes[msg.sender][newPoolIndex] += weight;
        totalWeights[newPoolIndex] += weight;
        gauges[newPoolIndex].weight += weight;

        // Reset the vote unlock time
        voteUnlockTime[msg.sender] = block.timestamp + VOTE_LOCK_PERIOD;

        emit VotesReallocated(msg.sender, oldPoolIndex, newPoolIndex, weight);
    }

    /// @notice Allows external parties to add bribes (incentives) to a gauge
    /// @param token Address of the ERC-20 token to be used as a bribe
    /// @param amount Amount of tokens to add as a bribe
    /// @param poolIndex Index of the pool to receive the bribe
    /// @param rewardDuration Duration over which rewards are distributed (in seconds)
    function addBribe(
        address token,
        uint256 amount,
        uint256 poolIndex,
        uint256 rewardDuration
    ) external {
        require(poolIndex < gauges.length, "Invalid pool index");
        require(amount > 0, "Amount must be greater than zero");
        require(rewardDuration >= 1 days, "Reward duration too short");

        IERC20(token).safeTransferFrom(msg.sender, gauges[poolIndex].gaugeAddress, amount);

        // Notify the gauge about the new bribe
        LiquidityGauge(gauges[poolIndex].gaugeAddress).notifyRewardAmount(token, amount, rewardDuration);

        emit BribeAdded(token, amount, poolIndex, rewardDuration);
    }

    /// @notice Retrieves the number of gauges
    /// @return The number of gauges
    function getGaugesCount() external view returns (uint256) {
        return gauges.length;
    }

    /// @notice Retrieves the weight of a specific gauge
    /// @param poolIndex Index of the pool
    /// @return Weight of the gauge
    function getGaugeWeight(uint256 poolIndex) external view returns (uint256) {
        require(poolIndex < gauges.length, "Invalid pool index");
        return gauges[poolIndex].weight;
    }
}
