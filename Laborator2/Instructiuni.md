# Smart Contracts in Solidity: A Fidelity Points Platform

Ghid pas cu pas pentru configurarea mediului și testarea unui smart contract de fidelitate scris în Solidity, folosind **MetaMask**, **Anvil**, **Remix IDE** și **Ethereum Sepolia**.

> **Scopul laboratorului:** să compilezi un contract Solidity, să îl implementezi pe o rețea de test, să îi apelezi funcțiile și să verifici tranzacțiile pe un explorator blockchain.
>
> **Notă:** folosește codul `FidelityPoints.sol` oferit de cadrul didactic, întocmai, fără modificări.

## Cuprins

- [1. Cum funcționează componentele](#1-cum-funcționează-componentele)
- [2. Înainte să începi](#2-înainte-să-începi)
- [3. Instalează și verifică Foundry](#3-instalează-și-verifică-foundry)
- [4. Configurează MetaMask](#4-configurează-metamask)
- [5. Obține Sepolia ETH](#5-obține-sepolia-eth)
- [6. Pornește Anvil și înțelege conturile locale](#6-pornește-anvil-și-înțelege-conturile-locale)
- [7. Deschide și compilează contractul în Remix](#7-deschide-și-compilează-contractul-în-remix)
- [8. Implementează contractul (Deploy)](#8-implementează-contractul-deploy)
- [9. Interacționează cu Deployed Contracts](#9-interacționează-cu-deployed-contracts)
- [10. Verifică tranzacțiile pe Etherscan](#10-verifică-tranzacțiile-pe-etherscan)
- [11. Probleme frecvente](#11-probleme-frecvente)
- [12. Checklist final](#12-checklist-final)
- [Resurse oficiale](#resurse-oficiale)

## 1. Cum funcționează componentele

| Componentă | Rol |
|---|---|
| **Solidity** | Limbajul în care sunt scrise regulile smart contract-ului. |
| **Remix IDE** | Editor în browser pentru scrierea, compilarea, implementarea și apelarea contractelor. |
| **MetaMask** | Portofel care gestionează conturi și semnează tranzacții. |
| **Anvil** | Nod Ethereum local pentru dezvoltare și testare. |
| **Sepolia** | Rețea publică Ethereum de test; folosește ETH de test, fără valoare reală intenționată. |
| **Faucet** | Serviciu care distribuie o cantitate limitată de monede de test. |
| **Etherscan Sepolia** | Explorator pentru căutarea tranzacțiilor și contractelor de pe Sepolia. |
| **Foundry** | Suită de unelte pentru dezvoltarea și testarea contractelor; include `forge`, `cast` și `anvil`. |

### Important: Anvil și Sepolia sunt rețele diferite

- **Anvil local** rulează pe calculatorul tău. În configurația standard, folosește `http://127.0.0.1:8545` și chain ID `31337`.
- **Sepolia** este o rețea publică de test, cu chain ID `11155111`.

Adresa unui cont poate fi aceeași pe ambele rețele dacă folosești aceeași cheie privată, dar **soldurile, contractele și tranzacțiile sunt independente**. Un contract implementat pe Anvil nu apare pe Etherscan Sepolia.

Pentru a urmări tranzacțiile pe Etherscan Sepolia, trebuie ca Remix/MetaMask să fie conectate la **Sepolia** în momentul deploy-ului și al tranzacțiilor. Anvil poate fi folosit separat pentru experimente locale.

## 2. Înainte să începi

Ai nevoie de:

- un browser compatibil cu extensia MetaMask;
- MetaMask instalat din [site-ul oficial](https://metamask.io/download/);
- acces la [Remix IDE](https://remix.ethereum.org/);
- un cont de test cu Sepolia ETH, dacă implementezi pe Sepolia;
- fișierul `FidelityPoints.sol` primit de la cadrul didactic;
- Foundry și Git, dacă laboratorul cere și lucrul din terminal.

Dacă lucrezi pe Windows și laboratorul cere Foundry în Linux, folosește distribuția Ubuntu din WSL, nu mediul intern `docker-desktop`.

## 3. Instalează și verifică Foundry

Instalează și verifică Foundry conform pașilor din **Laboratorul 1**.

## 4. Configurează MetaMask

### 4.1. Creează un portofel de test

1. Instalează extensia numai de pe [site-ul oficial MetaMask](https://metamask.io/download/).
2. Creează un wallet nou sau folosește un cont dedicat exclusiv testării.
3. Păstrează fraza de recuperare într-un loc sigur, offline.
4. Nu trimite fraza de recuperare sau cheia privată nimănui.

**Regulă de securitate:** nu folosi un cont cu fonduri reale pentru exerciții în care cheia privată este importată în unelte de dezvoltare. Conturile standard afișate de Anvil au chei private cunoscute și nu trebuie folosite niciodată pentru fonduri reale.

### 4.2. Activează Sepolia

1. Deschide MetaMask.
2. Activează afișarea rețelelor de test, dacă este dezactivată.
3. Selectează **Sepolia**.
4. Copiază adresa publică a contului pe care vrei să îl finanțezi.

Adresa publică poate fi distribuită pentru a primi fonduri de test. Cheia privată și fraza de recuperare nu trebuie distribuite.

## 5. Obține Sepolia ETH

Pentru a implementa un contract pe Sepolia, contul expeditor are nevoie de ETH de test pentru a plăti comisioanele.

Pentru minat, folosește faucet-ul: [sepolia-faucet.pk910.de](https://sepolia-faucet.pk910.de/).

1. Deschide faucet-ul.
2. Introdu adresa publică a contului din MetaMask.
3. Pornește minatul și așteaptă să se acumuleze fonduri.
4. Oprește minatul și solicită recompensa (claim).
5. Verifică în MetaMask că soldul Sepolia ETH a crescut.

Folosește adresa contului cu care vei plăti deploy-ul. Dacă schimbi ulterior contul selectat în MetaMask, soldul nu se transferă automat.

### Verifică soldul din terminal (opțional)

Dacă ai configurat un endpoint RPC pentru Sepolia, poți folosi:

```bash
cast balance ADRESA_CONTULUI --ether --rpc-url URL_RPC_SEPOLIA
```

Înlocuiește `ADRESA_CONTULUI` și `URL_RPC_SEPOLIA` cu valorile tale. Nu publica fișierele locale care conțin secrete sau configurații private.

## 6. Pornește Anvil și înțelege conturile locale

Anvil este un blockchain local destinat dezvoltării. Pornește-l într-un terminal:

```bash
anvil
```

În configurația standard, Anvil afișează mai multe adrese de test și cheile lor private, precum și endpointul RPC local. Lasă terminalul deschis cât timp folosești această rețea.

### 6.1. Importă un cont Anvil în MetaMask (doar pentru testare locală)

1. Copiază o adresă și cheia privată asociată din terminalul Anvil.
2. În MetaMask, alege opțiunea de importare a unui cont.
3. Introdu cheia privată a contului local.
4. Confirmă importarea.

Aceasta importă **cheia contului**, nu blockchain-ul Anvil. Nu folosi aceste chei pentru fonduri reale: ele sunt public cunoscute și destinate testării.

### 6.2. Adaugă rețeaua Anvil în MetaMask

Dacă vrei să interacționezi cu blockchain-ul local, adaugă o rețea cu următoarele valori standard:

| Câmp | Valoare |
|---|---|
| Network name | Anvil Local |
| RPC URL | `http://127.0.0.1:8545` |
| Chain ID | `31337` |
| Currency symbol | cel sugerat de MetaMask (selectează-l) |

Selectează apoi **Anvil Local** în MetaMask.

### 6.3. Când folosesc Anvil și când Sepolia?

- Folosește **Anvil Local** pentru teste rapide, locale, care nu trebuie publicate pe o rețea.
- Folosește **Sepolia** când dorești tranzacții pe rețeaua publică de test și să le verifici pe [Etherscan Sepolia](https://sepolia.etherscan.io/).

Nu confunda ETH-ul local de la Anvil cu Sepolia ETH. Soldurile sunt separate chiar dacă adresele coincid.

## 7. Deschide și compilează contractul în Remix

### 7.1. Creează fișierul

1. Accesează [Remix IDE](https://remix.ethereum.org/).
2. Deschide **File Explorer**.
3. Creează sau deschide fișierul `FidelityPoints.sol`.
4. Copiază codul furnizat de cadrul didactic.
5. Salvează fișierul.

Fișierul `.sol` conține cod Solidity. Citește-l înainte de deploy, în special constructorul, funcțiile care modifică punctele și eventualele verificări de acces.

### 7.2. Compilează

1. Deschide **Solidity Compiler**.
2. Alege o versiune de compilator compatibilă cu directiva `pragma` din fișier.
3. Apasă butonul albastru **Compile FidelityPoints.sol**.
4. Citește mesajele afișate și rezolvă erorile, dacă există.

Compilarea transformă codul Solidity în bytecode pentru EVM. **Nu implementează contractul pe blockchain** și nu trimite o tranzacție.

## 8. Implementează contractul (Deploy)

### 8.1. Alege mediul corect

În meniul din dreapta al Remix, deschide fila **Deploy & Run Transactions**.

1. La **Environment**, selectează **Browser extension – MetaMask**.
2. La **Account**, verifică să apară adresa contului tău din MetaMask.

Conectează MetaMask și verifică în fereastra wallet-ului:

- contul selectat;
- rețeaua selectată;
- soldul disponibil pentru comisioane.

Dacă vrei un contract pe Sepolia, selectează **Sepolia în MetaMask**. Dacă vrei un contract local, selectează **Anvil Local** și folosește conexiunea către nodul local.

### 8.2. Verifică parametrii de deploy

Codul primit de la cadrul didactic este complet și **nu se modifică**.

În Remix:

- selectează contractul `FidelityPoints`;
- completează câmpul pentru parametrul constructorului, conform cerinței laboratorului;
- verifică valoarea `Value`.

Câmpul `Value` din Remix este cantitatea de ETH trimisă împreună cu tranzacția de deploy. **Nu este valoarea punctelor de fidelitate și nici comisionul de gas.** Dacă nu este necesar să trimiți ETH, lasă-l la `0`.

### 8.3. Trimite tranzacția

1. Apasă **Deploy**.
2. MetaMask va afișa cererea de tranzacție.
3. Verifică rețeaua, contul și comisionul estimat.
4. Confirmă tranzacția.
5. Așteaptă rezultatul în Remix.

Dacă deploy-ul reușește, contractul apare în secțiunea **Deployed Contracts**. Copiază adresa contractului și păstreaz-o pentru pașii următori.

Adresa contractului este diferită de adresa wallet-ului care a făcut deploy-ul.

## 9. Interacționează cu Deployed Contracts

Deschide secțiunea **Deployed Contracts** și extinde instanța `FidelityPoints`. Remix afișează funcțiile contractului sub formă de butoane.

**Funcțiile exacte depind de fișierul primit la laborator.** Urmează descrierea de mai jos ca să înțelegi interfața, nu ca presupunere despre numele funcțiilor din contractul tău.

### 9.1. Funcții de citire

Funcțiile declarate `view` sau `pure` citesc date ori calculează un rezultat fără să modifice starea blockchain-ului.

De exemplu, un contract ar putea avea o funcție care returnează soldul de puncte pentru o adresă. Introduci adresa în câmpul funcției și apeși butonul pentru a vedea rezultatul.

Apelurile de citire făcute direct din Remix nu necesită, în mod obișnuit, o tranzacție on-chain și nu consumă gas din wallet.

### 9.2. Funcții care modifică starea

O funcție care acordă puncte, schimbă o valoare sau actualizează o înregistrare poate necesita o tranzacție.

Fluxul este:

1. Introduci parametrii ceruți de funcție.
2. Apeși butonul funcției.
3. Confirmi tranzacția în MetaMask, dacă este solicitată.
4. Aștepți procesarea.
5. Apelezi o funcție de citire pentru a verifica noua stare.

De exemplu, dacă o funcție primește o adresă și un număr de puncte, rezultatul depinde de implementare: poate adăuga puncte, poate seta o valoare sau poate respinge operația dacă nu ai permisiunea necesară.

Nu presupune că toate funcțiile pot fi apelate de orice cont. Contractul poate avea un administrator sau alte reguli de autorizare.

### 9.3. Ce înseamnă `Value` și parametrii funcției?

- **Parametrii funcției** sunt datele cerute de cod, cum ar fi o adresă sau un număr de puncte.
- **Value** este ETH-ul trimis odată cu tranzacția, dacă operația permite acest lucru.
- **Gas** măsoară resursele de calcul folosite pentru executarea tranzacției.

Aceste concepte sunt diferite. Introducerea numărului `100` într-un parametru pentru puncte nu înseamnă că trimiți 100 ETH.

### 9.4. Culorile butoanelor din Remix

În mod obișnuit, Remix folosește culori diferite pentru a distinge funcțiile de citire de tranzacțiile care modifică starea și de funcțiile `payable`. Culorile sunt doar indicii vizuale; verifică întotdeauna codul Solidity pentru a afla efectul real al unei funcții.

## 10. Verifică tranzacțiile pe Etherscan

Deschide [Etherscan Sepolia](https://sepolia.etherscan.io/).

### 10.1. Caută contractul

1. Copiază adresa din secțiunea `Deployed Contracts` din Remix.
2. Introdu adresa în bara de căutare Etherscan Sepolia.
3. Deschide pagina contractului, dacă tranzacția a fost confirmată pe Sepolia.

Dacă deploy-ul a fost făcut pe Anvil, adresa nu va avea o pagină corespunzătoare pe Etherscan Sepolia, deoarece Anvil este local.

### 10.2. Ce poți verifica?

- **Transaction Hash:** identificatorul tranzacției.
- **Status:** dacă tranzacția a reușit sau a eșuat.
- **From:** adresa care a trimis tranzacția.
- **To:** adresa destinatarului; la crearea unui contract, tranzacția poate avea un câmp `To` special sau poate fi afișată ca creare de contract.
- **Gas Used / Transaction Fee:** resursele consumate și comisionul.
- **Events / Logs:** evenimentele emise de contract, dacă acesta le emite.

După ce apelezi o funcție care modifică punctele, caută tranzacția după hash pentru a-i verifica statusul.

**Nu orice modificare a punctelor apare ca transfer de token.** Dacă punctele sunt păstrate într-un `mapping` în contract și nu sunt implementate ca token ERC-20, poți vedea tranzacția și eventualele evenimente fără să existe un transfer de token în lista standard de transferuri. Pentru soldul curent, folosește și funcția de citire din Remix.

Prezența contractului pe Etherscan nu înseamnă automat că sursa Solidity a fost verificată. Verificarea sursei este o operație separată.

## 11. Probleme frecvente

### Remix nu se conectează la MetaMask

- Verifică dacă extensia MetaMask este instalată și deblocată.
- Reîncarcă Remix și conectează wallet-ul din nou.
- Verifică permisiunile de conectare ale site-ului.

### Tranzacția eșuează din cauza fondurilor insuficiente

- Confirmă că MetaMask este pe rețeaua dorită.
- Verifică dacă acel cont are ETH pe rețeaua respectivă.
- Amintește-ți că ETH-ul local Anvil nu poate plăti comisioanele pe Sepolia.

### Contractul nu apare pe Etherscan

- Verifică dacă ai făcut deploy pe Sepolia, nu pe Anvil.
- Verifică dacă tranzacția de deploy a fost confirmată.
- Asigură-te că folosești [Etherscan Sepolia](https://sepolia.etherscan.io/), nu exploratorul Ethereum Mainnet.
- Caută adresa contractului, nu doar adresa wallet-ului.

### Nu înțeleg ce face un buton din `Deployed Contracts`

- Revino la fișierul Solidity.
- Caută numele funcției.
- Verifică parametrii, tipul de returnare și modificările de stare.
- Caută verificări precum `require`, modificatori de acces și evenimente `emit`.

### Am schimbat contul din MetaMask și nu mai văd soldul așteptat

Verifică adresa contului și rețeaua. Soldurile sunt asociate unei adrese pe o anumită rețea. Schimbarea contului sau a rețelei poate schimba datele afișate.

## 12. Checklist final

- [ ] Am instalat și verificat uneltele necesare.
- [ ] Am creat un wallet dedicat testării și am protejat fraza de recuperare.
- [ ] Am selectat rețeaua corectă în MetaMask.
- [ ] Am primit ETH de test pe rețeaua pe care vreau să lucrez.
- [ ] Am înțeles diferența dintre Anvil și Sepolia.
- [ ] Am deschis `FidelityPoints.sol` în Remix.
- [ ] Am compilat contractul fără erori.
- [ ] Am verificat contul, rețeaua și parametrii înainte de deploy.
- [ ] Am implementat contractul și am salvat adresa lui.
- [ ] Am testat funcțiile de citire și cele care modifică starea.
- [ ] Am verificat tranzacțiile pe exploratorul rețelei corecte.

## Resurse oficiale

- [MetaMask — descărcare](https://metamask.io/download/)
- [Remix IDE](https://remix.ethereum.org/)
- [Documentația Remix](https://remix-ide.readthedocs.io/)
- [Foundry Book](https://book.getfoundry.sh/)
- [Anvil — documentația Foundry](https://book.getfoundry.sh/anvil/)
- [Sepolia Etherscan](https://sepolia.etherscan.io/)
- [MetaMask Developer](https://developer.metamask.io/)

---

**Securitate:** folosește exclusiv conturi și fonduri de test pentru laborator. Nu publica chei private, fraze de recuperare, fișiere `.env` sau alte secrete în repository-ul GitHub.
