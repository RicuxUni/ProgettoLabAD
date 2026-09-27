per avviare la prima volta eseguito

docker compose up -d --build



### Creare un nuovo utente
Per creare un utente base con la sua password, apri un nuovo terminale (assicurati che il container stia girando) ed esegui:
```bash
sudo docker exec -it lalilulelo_ad samba-tool user create enrico Password123!
```

```bash
sudo docker exec -it lalilulelo_ad samba-tool user create massimo Password123!
```


Se tutto va bene, ti risponderà con: `User 'enrico' created successfully`.

### Altri comandi molto utili di `samba-tool`
Ecco qualche altro comando che ti tornerà sicuramente utile nel tuo laboratorio:

*   **Vedere la lista di tutti gli utenti nel dominio:**
    ```bash
    sudo docker exec -it lalilulelo_ad samba-tool user list
    ```
*   **Aggiungere un utente a un gruppo (es. Domain Admins):**
    ```bash
    sudo docker exec -it lalilulelo_ad samba-tool group addmembers "Domain Admins" enrico
    ```
*   **Vedere la lista dei gruppi:**
    ```bash
    sudo docker exec -it lalilulelo_ad samba-tool group list
    ```
*   **Resettare/Cambiare la password a un utente:**
    ```bash
    sudo docker exec -it lalilulelo_ad samba-tool user setpassword enrico --newpassword=1234567-A
    ```
*   **Abilitare un utente:**
    ```bash
    sudo docker exec lalilulelo_ad samba-tool user enable enrico
    ```
*   **Disabilitare un utente:**
    ```bash
    sudo docker exec lalilulelo_ad samba-tool user disable enrico
    ```

In alternativa, se preferisci un'interfaccia grafica e hai una macchina Windows collegata (joinata) a questo dominio o in rete, potresti usare i tool ufficiali Microsoft RSAT (Remote Server Administration Tools), in particolare "Utenti e computer di Active Directory", e collegarti a questo server proprio come se fosse un normale Domain Controller Windows!