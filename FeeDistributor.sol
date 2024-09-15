// Contract Inheritance:

// Inherits from Ownable to restrict certain functions to the owner (which can be set to the pool contract).
// Variables:

// lpToken: Reference to the LP token contract.
// totalFees: Mapping of tokens to the total fees collected.
// userFees: Mapping of users to tokens to the fees accrued.
// Functions:

// collectFee: Called by the pool contract to add collected fees to the total fees.
// claimFees: Allows users to claim their share of the fees based on their LP token balance.
// Events:

// FeesCollected: Emitted when fees are collected.
// FeesClaimed: Emitted when a user claims their fees.


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import statements
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title FeeDistributor
/// @notice Distributes fees collected from the pool to liquidity providers
contract FeeDistributor is Ownable {
    using SafeERC20 for IERC20;

    // Reference to the LP token (ERC20)
    IERC20 public lpToken;

    // Mapping from token address to total fees collected
    mapping(address => uint256) public totalFees;

    // Mapping from user address to token address to fees accrued
    mapping(address => mapping(address => uint256)) public userFees;

    // Events
    event FeesCollected(address indexed token, uint256 amount);
    event FeesClaimed(address indexed user, address indexed token, uint256 amount);

    /// @notice Initializes the contract with the LP token address
    /// @param _lpToken Address of the LP token
    constructor(address _lpToken) {
        lpToken = IERC20(_lpToken);
    }

    /// @notice Collects fees from the pool (called by the pool contract)
    /// @param token Address of the token for which fees are collected
    /// @param amount Amount of fees collected
    function collectFee(address token, uint256 amount) external onlyOwner {
        totalFees[token] = totalFees[token] + amount;
        emit FeesCollected(token, amount);
    }

    /// @notice Allows users to claim their accrued fees
    /// @param token Address of the token to claim fees in
    function claimFees(address token) external {
        uint256 userBalance = lpToken.balanceOf(msg.sender);
        uint256 totalSupply = lpToken.totalSupply();
        uint256 userShare = (totalFees[token] * userBalance) / totalSupply;

        require(userShare > 0, "No fees to claim");

        userFees[msg.sender][token] = userFees[msg.sender][token] + userShare;
        totalFees[token] = totalFees[token] - userShare;

        IERC20(token).safeTransfer(msg.sender, userShare);

        emit FeesClaimed(msg.sender, token, userShare);
    }
}
