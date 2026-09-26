per avviare la prima volta eseguito

docker compose up -d --build



### Creare un nuovo utente
Per creare un utente base con la sua password, apri un nuovo terminale (assicurati che il container stia girando) ed esegui:
```bash
docker exec -it lalilulelo_ad samba-tool user create nomeutente Password123!
```
*(Sostituisci `nomeutente` e `Password123!` con le credenziali che preferisci)*

Se tutto va bene, ti risponderà con: `User 'nomeutente' created successfully`.

### Altri comandi molto utili di `samba-tool`
Ecco qualche altro comando che ti tornerà sicuramente utile nel tuo laboratorio:

*   **Vedere la lista di tutti gli utenti nel dominio:**
    ```bash
    docker exec -it lalilulelo_ad samba-tool user list
    ```
*   **Aggiungere un utente a un gruppo (es. Domain Admins):**
    ```bash
    docker exec -it lalilulelo_ad samba-tool group addmembers "Domain Admins" nomeutente
    ```
*   **Vedere la lista dei gruppi:**
    ```bash
    docker exec -it lalilulelo_ad samba-tool group list
    ```
*   **Resettare/Cambiare la password a un utente:**
    ```bash
    docker exec -it lalilulelo_ad samba-tool user setpassword nomeutente --newpassword=NuovaPassw0rd!
    ```
*   **Abilitare un utente:**
    ```bash
    docker exec lalilulelo_ad samba-tool user enable mappopo
    ```
*   **Disabilitare un utente:**
    ```bash
    docker exec lalilulelo_ad samba-tool user disable mappopo
    ```

In alternativa, se preferisci un'interfaccia grafica e hai una macchina Windows collegata (joinata) a questo dominio o in rete, potresti usare i tool ufficiali Microsoft RSAT (Remote Server Administration Tools), in particolare "Utenti e computer di Active Directory", e collegarti a questo server proprio come se fosse un normale Domain Controller Windows!