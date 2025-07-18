// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IWMNT - Interfaccia per Wrapped MNT
 * @notice Interfaccia standard per il token WMNT (Wrapped MNT)
 * @dev Basata sul pattern standard WETH, permette di wrappare/unwrappare MNT nativo
 */
interface IWMNT is IERC20 {
    
    // =================================================================
    // CORE WRAP/UNWRAP FUNCTIONS
    // =================================================================
    
    /**
     * @notice Deposita MNT nativo e riceve WMNT
     * @dev Funzione payable - invia MNT nativo con la transazione
     */
    function deposit() external payable;
    
    /**
     * @notice Preleva MNT nativo bruciando WMNT
     * @param amount Quantità di WMNT da bruciare per ricevere MNT nativo
     */
    function withdraw(uint256 amount) external;
    
    // =================================================================
    // EVENTS
    // =================================================================
    
    /**
     * @notice Emesso quando MNT nativo viene depositato per WMNT
     * @param dst Indirizzo che riceve i WMNT
     * @param wad Quantità di MNT depositata
     */
    event Deposit(address indexed dst, uint256 wad);
    
    /**
     * @notice Emesso quando WMNT viene bruciato per MNT nativo
     * @param src Indirizzo che brucia i WMNT
     * @param wad Quantità di WMNT bruciata
     */
    event Withdrawal(address indexed src, uint256 wad);
}