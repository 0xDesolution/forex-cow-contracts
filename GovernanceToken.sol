// Governance Token: An ERC20 token that implements ERC20Votes and ERC20Permit from OpenZeppelin, allowing for voting capabilities and gasless approvals.

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import statements
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

/// @title GovernanceToken
/// @notice ERC20 token with voting capabilities for governance
contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes {
    constructor()
        ERC20("Forex Governance Token", "FGT")
        ERC20Permit("Forex Governance Token")
    {
        _mint(msg.sender, 1_000_000e18); // Mint initial supply to deployer
    }

    // The functions below are overrides required by Solidity.

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._burn(account, amount);
    }
}
