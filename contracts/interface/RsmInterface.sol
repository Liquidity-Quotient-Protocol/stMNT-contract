// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IRSM - Interfaccia per StakingMNT
 * @notice Solo le funzioni pubbliche utilizzabili dagli utenti
 * @dev Basata sul contratto: 0xeD884f0460A634C69dbb7def54858465808AACEf
 */
interface IRSM {
    // =================================================================
    // CORE DEPOSIT/WITHDRAW FUNCTIONS
    // =================================================================

    /**
     * @notice Deposita MNT nativo con lock flessibile
     * @param assets Quantità di MNT da depositare (deve essere uguale a msg.value)
     * @return Quantità di MNT depositata
     */
    function deposit(uint256 assets) external payable returns (uint256);

    /**
     * @notice Deposita MNT nativo con periodo di lock specifico
     * @param assets Quantità di MNT da depositare (deve essere uguale a msg.value)
     * @param duration Durata del lock in giorni
     * @param autoRenew Se true, il lock si rinnova automaticamente alla scadenza
     * @return Quantità di MNT depositata
     */
    function depositWithLockup(
        uint256 assets,
        uint256 duration,
        bool autoRenew
    ) external payable returns (uint256);

    /**
     * @notice Preleva MNT precedentemente depositati
     * @param assets Quantità di MNT da prelevare
     * @param receiver Indirizzo che riceverà gli MNT
     * @return Quantità di MNT prelevata
     */
    function withdraw(
        uint256 assets,
        address receiver
    ) external returns (uint256);

    // =================================================================
    // LOCKUP MANAGEMENT FUNCTIONS
    // =================================================================

    /**
     * @notice Converte tutti gli MNT flessibili in un nuovo lockup
     * @param duration Durata del lock in giorni
     * @param autoRenew Se abilitare il rinnovo automatico
     * @return True se l'operazione è riuscita
     */
    function convertFlexibleToLockup(
        uint256 duration,
        bool autoRenew
    ) external returns (bool);

    /**
     * @notice Estende la durata di un lock specifico
     * @param lockStart Timestamp di inizio del lock
     * @param amount Quantità del lock
     * @param duration Durata attuale in giorni
     * @param newDuration Nuova durata in giorni
     * @return True se l'operazione è riuscita
     */
    function extendLockupDuration(
        uint256 lockStart,
        uint256 amount,
        uint256 duration,
        uint256 newDuration
    ) external returns (bool);

    /**
     * @notice Imposta il rinnovo automatico per un lock specifico
     * @param lockStart Timestamp di inizio del lock
     * @param amount Quantità del lock
     * @param duration Durata del lock in giorni
     * @param autoRenew Se abilitare il rinnovo automatico
     * @return True se l'operazione è riuscita
     */
    function setLockupAutoRenew(
        uint256 lockStart,
        uint256 amount,
        uint256 duration,
        bool autoRenew
    ) external returns (bool);

    /**
     * @notice Imposta il rinnovo automatico per tutti i lockup dell'utente
     * @param autoRenew Se abilitare il rinnovo automatico
     * @return Numero di lockup modificati
     */
    function setAllLockupAutoRenew(bool autoRenew) external returns (uint256);

    // =================================================================
    // VIEW FUNCTIONS
    // =================================================================

    /**
     * @notice Verifica il cooldown di un utente
     * @param depositor Indirizzo dell'utente
     * @return inCooldown Se l'utente è in cooldown
     * @return remainingTime Tempo rimanente del cooldown in secondi
     */
    function userStakeCooldown(
        address depositor
    ) external view returns (bool inCooldown, uint256 remainingTime);

    /**
     * @notice Ottiene la quantità depositata da un utente
     * @param account Indirizzo dell'utente
     * @return Quantità totale depositata
     */
    function deposited(address account) external view returns (uint256);

    /**
     * @notice Ottiene il numero di lockup attivi per un utente
     * @param user Indirizzo dell'utente
     * @return Numero di lockup
     */
    function getUserLockUpsCount(address user) external view returns (uint256);

    /**
     * @notice Ottiene il deposito totale nel protocollo
     * @return Deposito totale in MNT
     */
    function totalDeposit() external view returns (uint256);

    /**
     * @notice Ottiene la quantità massima depositabile da un utente
     * @param user Indirizzo dell'utente
     * @return Quantità massima depositabile
     */
    function maxDeposit(address user) external view returns (uint256);
}
