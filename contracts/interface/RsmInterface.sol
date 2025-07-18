//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface IRSM {
    // SPDX-License-Identifier: MIT

    /**
     * @title Interfaccia Mantle Rewards Station
     * @notice Funzioni estratte dalla documentazione per interagire con la Rewards Station
     */

    // =================================================================
    // CORE LOCKING FUNCTIONS
    // =================================================================

    /**
     * @notice Blocca MNT nella Rewards Station
     * @dev Lock flessibile senza periodo fisso per mantenere liquidità
     * @param amount Quantità di MNT da bloccare
     */
    function lockMNT(uint256 amount) external;

    /**
     * @notice Sblocca MNT dalla Rewards Station
     * @dev Solo per MNT non soggetti a lock fissi
     * @param amount Quantità di MNT da sbloccare
     */
    function unlockMNT(uint256 amount) external;

    /**
     * @notice Visualizza l'MNT bloccato e il MNT Power dell'utente
     * @param user Indirizzo dell'utente
     * @return lockedAmount MNT attualmente bloccato
     * @return mntPower MNT Power totale dell'utente
     */
    function getLockStatus(
        address user
    ) external view returns (uint256 lockedAmount, uint256 mntPower);

    // =================================================================
    // MNT POWER ALLOCATION FUNCTIONS
    // =================================================================

    /**
     * @notice Alloca MNT Power a un pool di ricompense specifico
     * @dev Attualmente auto-allocato al pool attivo, in futuro manuale
     * @param poolId ID del pool di ricompense
     * @param mntPowerAmount Quantità di MNT Power da allocare
     */
    function allocateMNTPower(uint256 poolId, uint256 mntPowerAmount) external;

    /**
     * @notice Rimuove allocazione di MNT Power da un pool
     * @param poolId ID del pool di ricompense
     * @param mntPowerAmount Quantità di MNT Power da rimuovere
     */
    function deallocateMNTPower(
        uint256 poolId,
        uint256 mntPowerAmount
    ) external;

    /**
     * @notice Visualizza l'allocazione corrente di MNT Power per pool
     * @param user Indirizzo dell'utente
     * @param poolId ID del pool
     * @return allocatedPower MNT Power allocato al pool
     */
    function getAllocation(
        address user,
        uint256 poolId
    ) external view returns (uint256 allocatedPower);

    // =================================================================
    // REWARDS CLAIMING FUNCTIONS
    // =================================================================

    /**
     * @notice Riscuote le ricompense da un pool specifico
     * @dev Solo per pool nel periodo "Claiming"
     * @param poolId ID del pool da cui riscuotere
     * @return rewardAmount Quantità di ricompense riscossa
     */
    function claimRewards(
        uint256 poolId
    ) external returns (uint256 rewardAmount);

    /**
     * @notice Visualizza le ricompense disponibili per il claim
     * @param user Indirizzo dell'utente
     * @param poolId ID del pool
     * @return pendingRewards Ricompense in attesa di claim
     * @return rewardToken Indirizzo del token ricompensa
     */
    function getPendingRewards(
        address user,
        uint256 poolId
    ) external view returns (uint256 pendingRewards, address rewardToken);

    /**
     * @notice Riscuote tutte le ricompense disponibili da tutti i pool attivi
     * @return claimedPools Array degli ID dei pool da cui sono state riscossa ricompense
     * @return claimedAmounts Array delle quantità riscossa per ogni pool
     * @return rewardTokens Array dei token ricompensa corrispondenti
     */
    function claimAllRewards()
        external
        returns (
            uint256[] memory claimedPools,
            uint256[] memory claimedAmounts,
            address[] memory rewardTokens
        );

    // =================================================================
    // VIEW FUNCTIONS - POOL INFORMATION
    // =================================================================

    /**
     * @notice Ottiene informazioni sui pool attivi
     * @return activePoolIds Array degli ID dei pool attualmente attivi
     * @return poolNames Array dei nomi dei pool
     * @return rewardTokens Array dei token ricompensa per ogni pool
     */
    function getActivePools()
        external
        view
        returns (
            uint256[] memory activePoolIds,
            string[] memory poolNames,
            address[] memory rewardTokens
        );

    /**
     * @notice Verifica se un pool è in fase di claiming
     * @param poolId ID del pool da verificare
     * @return isClaiming True se il pool è in fase di claiming
     */
    function isPoolClaiming(
        uint256 poolId
    ) external view returns (bool isClaiming);

    /**
     * @notice Ottiene dettagli specifici di un pool
     * @param poolId ID del pool
     * @return poolName Nome del pool
     * @return rewardToken Token ricompensa del pool
     * @return totalAllocatedPower MNT Power totale allocato al pool
     * @return rewardRate Tasso di ricompense per unità di tempo
     */
    function getPoolDetails(
        uint256 poolId
    )
        external
        view
        returns (
            string memory poolName,
            address rewardToken,
            uint256 totalAllocatedPower,
            uint256 rewardRate
        );

    // =================================================================
    // UTILITY FUNCTIONS
    // =================================================================

    /**
     * @notice Calcola il MNT Power che si otterrebbe con un certo lock
     * @param amount Quantità di MNT da bloccare
     * @param lockDays Giorni di lock (0 per flessibile)
     * @return mntPower MNT Power risultante
     */
    function calculateMNTPower(
        uint256 amount,
        uint256 lockDays
    ) external pure returns (uint256 mntPower);

    /**
     * @notice Verifica se l'utente può sbloccare una certa quantità
     * @param user Indirizzo dell'utente
     * @param amount Quantità da sbloccare
     * @return canUnlock True se può sbloccare la quantità richiesta
     */
    function canUnlock(
        address user,
        uint256 amount
    ) external view returns (bool canUnlock);

    // =================================================================
    // EMERGENCY FUNCTIONS
    // =================================================================

    /**
     * @notice Sblocca tutto l'MNT disponibile (solo quello flessibile)
     * @return unlockedAmount Quantità sbloccata
     */
    function emergencyUnlockAll() external returns (uint256 unlockedAmount);

    /**
     * @notice Calcola le ricompense MNT pending per un utente
     * @dev Formula: (Your Locked MNT Power / Total MNT Power Locked per day) * Daily Rewards Prize Pool
     * @param user Indirizzo dell'utente
     * @param poolId ID del pool MNT Reward Booster
     * @return pendingRewards Ricompense MNT pending (time-weighted)
     */
    function calculatePendingRewards(
        address user,
        uint256 poolId
    ) external view returns (uint256 pendingRewards);

    // =================================================================
    // NOTES DALLA DOCUMENTAZIONE
    // =================================================================

    /*
PUNTI CHIAVE DALLA DOCUMENTAZIONE:

1. LOCK FLESSIBILE:
   - Moltiplicatore 1x (nessun boost)
   - Può essere sbloccato in qualsiasi momento
   - Ideale per mantenere liquidità

2. ALLOCAZIONE AUTOMATICA:
   - Al momento, MNT Power viene auto-allocato al pool attivo
   - In futuro sarà necessaria allocazione manuale percentuale

3. CLAIMING:
   - Le ricompense possono essere riscossa solo durante il periodo "Claiming"
   - Indicato dall'icona "Claiming" sulla homepage

4. CALCOLO RICOMPENSE:
   - Basato su calcolo time-weighted del MP bloccato
   - Le ricompense si accumulano ogni secondo

5. ESEMPI DI RICOMPENSE:
   - ENA tokens (da Ethena Labs)
   - EIGEN tokens 
   - COOK tokens (da mETH Protocol)
   - mShards (convertibili in ENA)

6. FLESSIBILITÀ:
   - Depositi multipli supportati
   - Mix di lock flessibili e fissi possibile
   - Transizione automatica da fisso a flessibile alla scadenza
*/
}
