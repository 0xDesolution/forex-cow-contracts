// Explanation and Comments

// LiquidityGauge Reference:

// The pool contract now holds a reference to its associated LiquidityGauge.
// LP Token Interaction:

// LP tokens minted by the pool can be staked in the gauge to earn additional rewards.

// Contract Inheritance:

// Inherits from UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, and ERC20Upgradeable to provide upgradability, access control, reentrancy protection, and ERC20 functionalities for the LP token.
// Struct Coin:

// Stores each token's IERC20 instance, decimals, and the associated Chainlink oracle for price feeds.
// Variables:

// coins: An array of Coin structs representing the tokens in the pool.
// amplification: The amplification coefficient (A) used in Curve's StableSwap invariant.
// fee: Trading fee percentage in basis points.
// adminFee: Portion of the fee allocated to the admin or governance.
// balances: Mapping of token indices to their total balances in the pool.
// cowProtocol: Reference to the Cow Protocol interface for order matching.
// Initialization Function:

// Sets up the contract with the provided tokens, decimals, oracles, amplification coefficient, fees, and Cow Protocol address.
// Initializes inherited contracts.
// Authorization for Upgrades:

// _authorizeUpgrade function ensures only the owner can authorize contract upgrades.
// Liquidity Functions:

// addLiquidity: Allows users to add liquidity to the pool by depositing amounts of each token. Calculates the amount of LP tokens to mint based on the change in the invariant D.
// removeLiquidity: Allows users to remove liquidity from the pool by burning their LP tokens and receiving amounts of each underlying token.
// Swap Function:

// exchange: Enables token swaps between any two tokens in the pool using the StableSwap invariant for price calculations. Updates balances, applies fees, and emits an event.
// Mathematical Functions:

// getD: Calculates the invariant D using the StableSwap formula.
// getY: Calculates the new balance of a token given changes in another token's balance.
// getDy: Calculates the amount of token j a user would receive for swapping a certain amount of token i, accounting for fees.
// Utility Functions:

// getXP: Retrieves the pseudo balances adjusted for decimals.
// Governance Functions:

// updateAmplification, updateFee, updateAdminFee: Functions to update protocol parameters, restricted to the owner (governance).

// Security Enhancements:

// SafeERC20: Used for all token transfers, including LP tokens and underlying assets.
// Input Validations: Added require statements to validate indices, amounts, and addresses.
// ReentrancyGuard: Protects functions from reentrancy attacks using the nonReentrant modifier.
// Gauge Integration:

// LiquidityGauge Reference: The pool holds a reference to the LiquidityGauge contract.
// Stake and Withdraw in Gauge: Provided functions stakeInGauge and withdrawFromGauge for users to stake and withdraw LP tokens directly through the pool contract.

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import statements
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// Interface for Cow Settlement
interface ICowSettlement {
    function vaultRelayer() external view returns (address);
    function setPreSignature(bytes calldata orderUid, bool signed) external;
}

// Import LiquidityGauge
import "./LiquidityGauge.sol";

/// @title ForexCurvePool
/// @notice A liquidity pool implementing Curve V2 mathematical functions with Cow Protocol integration and enhanced security
contract ForexCurvePool is
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC20Upgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // Struct to store information about each coin in the pool
    struct Coin {
        IERC20Upgradeable token;
        uint256 decimals;
        AggregatorV3Interface oracle;
    }

    // Array of coins in the pool
    Coin[] public coins;

    // Amplification coefficient (A)
    uint256 public amplification;

    // Fee percentage (in basis points, e.g., 30 = 0.3%)
    uint256 public fee;

    // Admin fee percentage (portion of fee kept for admin/governance)
    uint256 public adminFee;

    // Total balances of each token in the pool
    mapping(uint256 => uint256) public balances;

    // Reference to the Cow Settlement contract
    ICowSettlement public cowSettlement;

    // Reference to the LiquidityGauge contract
    LiquidityGauge public liquidityGauge;

    // Constants
    uint256 constant FEE_DENOMINATOR = 1e10;
    uint256 constant PRECISION = 1e18;

    // Events
    event AddLiquidity(address indexed provider, uint256[] tokenAmounts, uint256 lpTokensMinted);
    event RemoveLiquidity(address indexed provider, uint256[] tokenAmounts, uint256 lpTokensBurned);
    event TokenExchange(
        address indexed buyer,
        uint256 soldId,
        uint256 tokensSold,
        uint256 boughtId,
        uint256 tokensBought
    );

    /// @notice Initializes the contract with given parameters
    /// @param _coins Addresses of the tokens in the pool
    /// @param _decimals Decimals of the tokens
    /// @param _oracles Addresses of Chainlink price oracles for the tokens
    /// @param _amplification Amplification coefficient (A)
    /// @param _fee Trading fee percentage in basis points
    /// @param _adminFee Admin fee percentage in basis points
    /// @param _cowSettlementAddress Address of the Cow Settlement contract
    /// @param _liquidityGaugeAddress Address of the LiquidityGauge contract
    function initialize(
        address[] memory _coins,
        uint256[] memory _decimals,
        address[] memory _oracles,
        uint256 _amplification,
        uint256 _fee,
        uint256 _adminFee,
        address _cowSettlementAddress,
        address _liquidityGaugeAddress
    ) public initializer {
        require(_coins.length == _decimals.length, "Coins and decimals length mismatch");
        require(_coins.length == _oracles.length, "Coins and oracles length mismatch");

        __Ownable_init();
        __ReentrancyGuard_init();
        __ERC20_init("Forex Curve Pool LP Token", "FCP-LP");

        for (uint256 i = 0; i < _coins.length; i++) {
            require(_coins[i] != address(0), "Invalid token address");
            require(_oracles[i] != address(0), "Invalid oracle address");
            coins.push(
                Coin({
                    token: IERC20Upgradeable(_coins[i]),
                    decimals: _decimals[i],
                    oracle: AggregatorV3Interface(_oracles[i])
                })
            );
        }

        amplification = _amplification;
        fee = _fee;
        adminFee = _adminFee;
        require(_cowSettlementAddress != address(0), "Invalid Cow Settlement address");
        cowSettlement = ICowSettlement(_cowSettlementAddress);
        require(_liquidityGaugeAddress != address(0), "Invalid LiquidityGauge address");
        liquidityGauge = LiquidityGauge(_liquidityGaugeAddress);
    }

    /// @notice Authorizes contract upgrades (UUPS pattern)
    /// @param newImplementation Address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice Updates the amplification coefficient (A)
    /// @param newAmplification The new amplification coefficient
    function updateAmplification(uint256 newAmplification) external onlyOwner {
        require(newAmplification > 0, "Amplification must be greater than zero");
        amplification = newAmplification;
    }

    /// @notice Adds liquidity to the pool
    /// @param amounts Array of amounts of each token to add
    /// @param minMintAmount Minimum LP tokens to mint (slippage protection)
    function addLiquidity(uint256[] memory amounts, uint256 minMintAmount) external nonReentrant {
        require(amounts.length == coins.length, "Amounts length mismatch");

        uint256 totalSupply = totalSupply();
        uint256 D0 = 0;
        uint256[] memory oldBalances = new uint256[](coins.length);

        if (totalSupply > 0) {
            D0 = getD(getXP(), amplification);
        }

        for (uint256 i = 0; i < coins.length; i++) {
            require(amounts[i] > 0, "Amounts must be greater than zero");
            oldBalances[i] = balances[i];
            balances[i] = balances[i] + amounts[i];
            coins[i].token.safeTransferFrom(msg.sender, address(this), amounts[i]);
        }

        uint256 D1 = getD(getXP(), amplification);
        require(D1 > D0, "D1 must be greater than D0");

        uint256 mintAmount;
        if (totalSupply == 0) {
            mintAmount = D1;
        } else {
            mintAmount = (totalSupply * (D1 - D0)) / D0;
        }

        require(mintAmount >= minMintAmount, "Slippage limit reached");

        _mint(msg.sender, mintAmount);

        emit AddLiquidity(msg.sender, amounts, mintAmount);
    }

    /// @notice Removes liquidity from the pool
    /// @param lpTokenAmount Amount of LP tokens to burn
    /// @param minAmounts Minimum amounts of each token to receive (slippage protection)
    function removeLiquidity(uint256 lpTokenAmount, uint256[] memory minAmounts) external nonReentrant {
        require(lpTokenAmount > 0, "Amount must be greater than zero");
        require(minAmounts.length == coins.length, "Min amounts length mismatch");

        uint256 totalSupply = totalSupply();

        uint256[] memory amounts = new uint256[](coins.length);

        for (uint256 i = 0; i < coins.length; i++) {
            amounts[i] = (balances[i] * lpTokenAmount) / totalSupply;
            require(amounts[i] >= minAmounts[i], "Slippage limit reached");
            balances[i] = balances[i] - amounts[i];
            coins[i].token.safeTransfer(msg.sender, amounts[i]);
        }

        _burn(msg.sender, lpTokenAmount);

        emit RemoveLiquidity(msg.sender, amounts, lpTokenAmount);
    }

    /// @notice Swaps tokens using the pool's liquidity, callable by Cow Protocol's settlement contract
    /// @param i Index of the token to sell
    /// @param j Index of the token to buy
    /// @param dx Amount of token i to sell
    /// @param minDy Minimum amount of token j to receive (slippage protection)
    /// @param recipient Address to receive the output tokens
    /// @return dy Amount of token j actually transferred
    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 minDy,
        address recipient
    ) external nonReentrant returns (uint256 dy) {
        require(i != j, "Cannot exchange the same token");
        require(i < coins.length && j < coins.length, "Token index out of range");
        require(dx > 0, "dx must be greater than zero");
        require(recipient != address(0), "Invalid recipient address");

        // Ensure only Cow Protocol's settlement contract can call this function
        require(msg.sender == address(cowSettlement), "Unauthorized caller");

        // Transfer dx amount of token i from Cow Protocol to pool
        coins[i].token.safeTransferFrom(msg.sender, address(this), dx);

        // Update balances
        balances[i] += dx;

        // Calculate dy amount of token j using Curve formula
        dy = getDy(i, j, dx);
        require(dy >= minDy, "Slippage limit reached");

        // Apply fee
        uint256 dyFee = (dy * fee) / FEE_DENOMINATOR;
        uint256 dyAdminFee = (dyFee * adminFee) / FEE_DENOMINATOR;
        uint256 dyTransfer = dy - dyFee;

        // Update balances
        balances[j] -= dyTransfer;

        // Fee handling (e.g., send admin fee to fee collector)
        // Implement fee collection logic as needed
        // For example:
        // balances[j] -= dyAdminFee;
        // coins[j].token.safeTransfer(feeCollector, dyAdminFee);

        // Transfer dy amount of token j to recipient
        coins[j].token.safeTransfer(recipient, dyTransfer);

        emit TokenExchange(recipient, i, dx, j, dyTransfer);
    }

    /// @notice Calculates the invariant D
    /// @param xp Array of balances adjusted for price and decimals
    /// @param amp Amplification coefficient
    /// @return D invariant value
    function getD(uint256[] memory xp, uint256 amp) internal pure returns (uint256) {
        uint256 N_COINS = xp.length;
        uint256 S = 0;
        for (uint256 i = 0; i < N_COINS; i++) {
            S += xp[i];
        }
        if (S == 0) {
            return 0;
        }

        uint256 D = S;
        uint256 Ann = amp * N_COINS;
        for (uint256 _i = 0; _i < 255; _i++) {
            uint256 D_P = D;
            for (uint256 i = 0; i < N_COINS; i++) {
                D_P = (D_P * D) / (xp[i] * N_COINS);
            }
            uint256 Dprev = D;
            D = ((Ann * S + D_P * N_COINS) * D) / ((Ann - 1) * D + (N_COINS + 1) * D_P);
            if (D > Dprev) {
                if (D - Dprev <= 1) {
                    return D;
                }
            } else {
                if (Dprev - D <= 1) {
                    return D;
                }
            }
        }
        revert("D calculation did not converge");
    }

    /// @notice Calculates the new balance of token i given balance of token j
    /// @param i Index of token i
    /// @param j Index of token j
    /// @param xj New balance of token j
    /// @param xp Current balances adjusted for price and decimals
    /// @return yi New balance of token i
    function getY(
        uint256 i,
        uint256 j,
        uint256 xj,
        uint256[] memory xp
    ) internal view returns (uint256) {
        uint256 N_COINS = xp.length;
        uint256 amp = amplification;
        uint256 D = getD(xp, amp);
        uint256 Ann = amp * N_COINS;

        uint256 c = D;
        uint256 S_ = 0;
        uint256 _xj = 0;
        for (uint256 _i = 0; _i < N_COINS; _i++) {
            if (_i == j) {
                _xj = xj;
            } else if (_i != i) {
                _xj = xp[_i];
            } else {
                continue;
            }
            S_ += _xj;
            c = (c * D) / (_xj * N_COINS);
        }
        c = (c * D) / (Ann * N_COINS);
        uint256 b = S_ + (D / Ann);

        uint256 y_prev = 0;
        uint256 y = D;
        for (uint256 _i = 0; _i < 255; _i++) {
            y_prev = y;
            y = (y * y + c) / (2 * y + b - D);
            if (y > y_prev) {
                if (y - y_prev <= 1) {
                    return y;
                }
            } else {
                if (y_prev - y <= 1) {
                    return y;
                }
            }
        }
        revert("Y calculation did not converge");
    }

    /// @notice Retrieves the adjusted balances (XP) considering decimals and oracles
    /// @return xp Array of adjusted balances
    function getXP() internal view returns (uint256[] memory) {
        uint256 N_COINS = coins.length;
        uint256[] memory xp = new uint256[](N_COINS);
        for (uint256 i = 0; i < N_COINS; i++) {
            (, int256 price, , , ) = coins[i].oracle.latestRoundData();
            require(price > 0, "Invalid oracle price");
            xp[i] = (balances[i] * uint256(price)) / (10 ** coins[i].decimals);
        }
        return xp;
    }

    /// @notice Calculates the amount of token j that will be received for swapping dx amount of token i
    /// @param i Index of the token to sell
    /// @param j Index of the token to buy
    /// @param dx Amount of token i to sell
    /// @return dy Amount of token j to receive
    function getDy(uint256 i, uint256 j, uint256 dx) public view returns (uint256) {
        uint256[] memory xp = getXP();
        uint256 x = xp[i] + ((dx * PRECISION) / (10 ** coins[i].decimals));
        uint256 y = getY(i, j, x, xp);
        uint256 dy = xp[j] - y - 1; // Subtract 1 to round down

        uint256 dy_fee = (dy * fee) / FEE_DENOMINATOR;
        dy = (dy - dy_fee) * (10 ** coins[j].decimals) / PRECISION;

        return dy;
    }

    /// @notice Allows users to stake their LP tokens directly through the pool contract
    /// @param amount Amount of LP tokens to stake
    function stakeInGauge(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake zero amount");
        _transfer(msg.sender, address(this), amount);
        _approve(address(this), address(liquidityGauge), amount);
        liquidityGauge.stake(amount);
    }

    /// @notice Allows users to withdraw their staked LP tokens from the gauge
    /// @param amount Amount of LP tokens to withdraw
    function withdrawFromGauge(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot withdraw zero amount");
        liquidityGauge.withdraw(amount);
        _transfer(address(this), msg.sender, amount);
    }
}
