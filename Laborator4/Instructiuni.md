# Contracte inteligente în Solidity: interacțiunea dintre contracte, erori, evenimente și costuri de gas

## Noțiuni de bază despre Solidity

Acest laborator continuă platforma de puncte de fidelitate realizată în Laboratorul 3. Punctul de plecare îl reprezintă cele două contracte care rezolvă exercițiile anterioare: `FidelityPointsFinal.sol` și `CatalogFinal.sol`. La Pasul 1, fișierele și contractele vor fi redenumite `FidelityPoints`, respectiv `Catalog`. Mai întâi, cele două contracte sunt conectate, astfel încât un client să poată **folosi punctele pentru a cumpăra produse din catalog**. Apoi, proiectul este extins cu evenimente, o gestionare mai precisă a erorilor și optimizări ale consumului de gas.

### Modificatorii de funcții

Un **modificator** schimbă comportamentul unei funcții într-un mod declarativ. Cel mai adesea, verifică o condiție înainte ca funcția să-și execute corpul [1]. Modificatorul `onlyAdmin` din Laboratorul 3 este un exemplu tipic:

```solidity
modifier onlyAdmin() {
    if (msg.sender != admin) revert NotAdmin(msg.sender);
    _;
}
```

- Marcajul special **`_;`** este substituentul pentru corpul funcției asupra căreia este aplicat modificatorul: arată unde trebuie să se execute (sau să se reia) codul funcției originale. Ordinea execuției este: (1) rulează instrucțiunile modificatorului aflate înainte de `_;`; (2) la `_;`, se execută corpul funcției originale; (3) după ce corpul funcției se încheie, execuția revine în modificator și continuă cu instrucțiunile aflate după `_;`, dacă există. Așadar, `_;` nu apelează funcția de la început și nu o repornește; marchează locul în care este inserat corpul funcției.

De exemplu, pentru `function addPoints(...) external onlyAdmin { ... }`, execuția verifică mai întâi condiția din `onlyAdmin`. Dacă verificarea trece, la `_;` se execută corpul lui `addPoints`. Dacă verificarea eșuează și se execută `revert`, corpul lui `addPoints` nu este executat.
- Un modificator poate primi **argumente**. Acestea pot fi expresii care folosesc parametrii funcției, de exemplu `function spendPoints(uint _points) external validAmount(_points)`.
- O funcție poate avea mai mulți modificatori, scriși unul după altul, de exemplu `function addPoints(...) public onlyAdmin whenNotPaused`. Aceștia se execută **în ordinea în care sunt declarați în semnătura funcției**. Prima condiție care eșuează determină eroarea primită de apelant.
- Codul unui modificator este, în general, **inserat în codul fiecărei funcții** care îl folosește. Dacă modificatorul este lung și apare pe multe funcții, bytecode-ul contractului poate deveni mai mare, ceea ce mărește costul publicării. O soluție de comparat este mutarea logicii într-o funcție `internal`, apelată din modificator.

### Erori și operația `revert`

Când apare o eroare, EVM-ul execută un **revert** al apelului curent: toate modificările de stare efectuate în cadrul acelui apel sunt anulate, iar apelantului îi sunt returnate datele erorii [2]. Solidity oferă următoarele mecanisme:

- **`require(condition, "message")`** declanșează un `revert` cu o eroare de tip `Error(string)` dacă expresia este falsă. Începând cu Solidity 0.8.26, în locul mesajului se poate transmite și o eroare personalizată: `require(condition, CustomError(args))`. `require` este folosit pentru a valida parametrii, starea contractului și rezultatele apelurilor către alte contracte.
- **`revert CustomError(args)`** și **`revert("message")`** declanșează explicit un `revert`; de obicei, sunt folosite într-un bloc `if` atunci când o condiție trebuie să ducă la eșec.
- **`assert(condition)`** declanșează un `revert` cu o eroare `Panic(uint256)` și codul `0x01` dacă expresia este falsă. Se folosește pentru **invariante**: condiții care ar trebui să fie adevărate dacă implementarea este corectă. De exemplu, numărul total de puncte nu ar trebui să fie mai mic decât soldul de puncte al unui singur client. Un `assert` eșuat indică, de regulă, o problemă în logică, nu un parametru introdus greșit de utilizator.
- **Erorile personalizate** (*custom errors*) se declară cu `error Nume(parametri);`, în interiorul sau în afara unui contract. În general, sunt mai ieftine decât mesajele text atât la publicare, cât și la execuție: datele erorii conțin un **selector** de 4 octeți (primii patru octeți din hash-ul Keccak-256 al semnăturii, de exemplu `NotAdmin(address)`) urmat de argumentele codificate ABI, nu un șir de caractere complet.

Compilatorul generează automat erori `Panic` în anumite situații. Codurile uzuale sunt: `0x01` pentru un `assert` eșuat, `0x11` pentru depășire sau scădere sub limita unui tip numeric (de exemplu `p.stock -= amount` când `amount > p.stock`), `0x12` pentru împărțirea la zero și `0x32` pentru accesarea unui element cu un index în afara limitelor tabloului.

Dacă un contract apelează o funcție din alt contract, iar funcția apelată declanșează un `revert`, eroarea se **propagă înapoi către apelant** (*bubbles up*). În lipsa unei gestionări prin `try`/`catch`, și funcția apelantă eșuează, transmițând aceleași date ale erorii.

### Instrucțiunea `try`/`catch`

Un apel extern care eșuează poate fi gestionat cu instrucțiunea `try`/`catch` [3]:

```solidity
try catalog.decreaseStock(code, quantity) {
    // se execută dacă apelul reușește
} catch Error(string memory reason) {
    // revert("...") sau require(false, "...") în contractul apelat
} catch Panic(uint errorCode) {
    // assert, overflow, împărțire la zero, index în afara limitelor
} catch (bytes memory lowLevelData) {
    // orice altă eroare, inclusiv erorile personalizate
}
```

Dacă funcția apelată returnează valori, acestea se declară după cuvântul-cheie `returns`, de exemplu `try catalog.getPrice(code) returns (uint price) { ... }`. Erorile personalizate nu au o clauză `catch` dedicată; ele ajung în clauza generală `catch (bytes memory lowLevelData)`. Pentru a identifica o astfel de eroare, se pot compara primii patru octeți ai datelor cu selectorul erorii, de exemplu `bytes4(lowLevelData) == Catalog.ProductNotFound.selector`.

`try` se poate folosi numai pentru apeluri de funcții **externe** și pentru crearea unui contract prin `new`. Erorile care apar chiar în contractul apelant — de exemplu, în timpul calculării argumentelor sau al decodificării valorilor returnate — nu sunt prinse de aceste clauze. De asemenea, dacă funcția apelantă declanșează ulterior un `revert`, toate modificările făcute de ea sunt anulate, inclusiv cele efectuate în blocul `catch`.

### Evenimente

**Evenimentele** înregistrează informații în **jurnalele** (*logs*) unei tranzacții [4]. Un eveniment este declarat folosind `event` și emis cu `emit`:

```solidity
event PointsAdded(address indexed client, uint amount);

emit PointsAdded(client, _points);
```

Fiecare înregistrare din jurnal conține adresa contractului care a emis-o, o listă de cel mult patru **`topics`** și un câmp **`data`** [5]:

- primul `topic` este hash-ul Keccak-256 al semnăturii evenimentului, de exemplu `keccak256("PointsAdded(address,uint256)")`. Acesta poate fi calculat cu `cast sig-event`;
- fiecare parametru marcat **`indexed`** devine un `topic` (pot exista cel mult trei parametri `indexed` pentru un eveniment); pentru tipurile de referință, precum `string`, `topic` conține hash-ul valorii, nu valoarea propriu-zisă;
- ceilalți parametri sunt codificați conform ABI și stocați în câmpul `data`.

Aplicațiile pot filtra jurnalele după adresa contractului și după `topics` — de exemplu, pentru a obține toate evenimentele `PointsAdded` ale unui anumit client — și se pot abona la evenimente noi pentru a reacționa la tranzacții. Jurnalele sunt mult mai ieftine decât stocarea persistentă (vezi costurile de gas de mai jos), dar **contractele nu le pot citi direct**. Ele sunt destinate aplicațiilor din afara blockchainului (*off-chain*). Orice informație pe care un contract trebuie să o folosească ulterior trebuie păstrată în storage.

### Interacțiunea dintre contracte

Un contract poate apela funcțiile altui contract dacă îi cunoaște adresa și interfața [6, 7]. Interfața se declară, de regulă, cu cuvântul-cheie `interface` și conține numai declarațiile funcțiilor necesare:

```solidity
interface ICatalog {
    function getPrice(bytes32 code) external view returns (uint);
    function decreaseStock(bytes32 code, uint amount) external;
}
```

O adresă poate fi convertită la tipul interfeței, de exemplu `ICatalog catalog = ICatalog(catalogAddress)`. Apoi, funcțiile pot fi apelate prin această variabilă, ca în `catalog.getPrice(code)`. Compilatorul codifică apelul (selectorul și argumentele), execută instrucțiunea EVM `CALL` — sau `STATICCALL` pentru funcții `view` și `pure` —, verifică rezultatul și decodifică valorile returnate. Codul sursă al contractului `Catalog` nu trebuie să fie disponibil; interfața trebuie doar să corespundă ABI-ului contractului apelat.

Proprietăți importante ale apelurilor externe:

- În contractul apelat, **`msg.sender` este adresa contractului care face apelul**, nu adresa clientului care a inițiat tranzacția. Expeditorul inițial poate fi identificat prin `tx.origin`, dar acesta nu trebuie folosit pentru autorizare: un contract intermediar ar putea exploata această verificare și ar putea acționa în numele clientului.
- Contractul apelat poate fi rău intenționat sau poate apela înapoi contractul apelant înainte ca primul apel să se încheie (**reentrancy**). De aceea, se recomandă ordinea **checks–effects–interactions**: verifică mai întâi condițiile, actualizează apoi starea contractului și efectuează apelurile externe abia la final [8].
- Un apel extern costă considerabil mai mult decât unul intern: este necesar accesul la adresa contractului apelat (2.600 gas la prima accesare într-o tranzacție), iar argumentele și rezultatele trebuie codificate și decodificate. Un apel de forma `this.f()` este tot un apel extern, chiar dacă funcția `f` aparține aceluiași contract.
- O funcție `view` nu consumă gas de tranzacție atunci când este apelată prin `eth_call` (de exemplu, cu `cast call`). Totuși, **consumă gas** atunci când este apelată dintr-o tranzacție, de exemplu când `redeem` apelează `catalog.getPrice`.

### Organizarea stocării (`storage layout`)

Stocarea unui contract este alcătuită din 2²⁵⁶ **sloturi** a câte 32 de octeți, inițial egale cu zero. Compilatorul atribuie sloturi variabilelor de stare în funcție de ordinea declarațiilor și de regulile următoare [9]:

- Tipurile de valoare ocupă numărul de octeți necesar tipului lor, iar variabilele consecutive sunt **grupate** (*packed*) în același slot dacă încap. De exemplu, `address admin` (20 de octeți), `bool paused` (1 octet) și `uint64 lastUpdate` (8 octeți), declarate consecutiv, pot ocupa împreună un singur slot. Un `uint` (`uint256`) ocupă întotdeauna un slot întreg.
- Structurile (`struct`) și tablourile încep întotdeauna de la un slot nou, iar variabila declarată după ele începe, la rândul ei, de la un slot nou. Câmpurile unei structuri respectă aceleași reguli de grupare. În `Catalog`, un `Product` ocupă 5 sloturi (`code`, `description`, `price`, `inStock`, `stock`), iar un `Promo` ocupă 4 sloturi, deși `state` are nevoie de un singur octet.
- Variabilele `constant` și `immutable` nu sunt păstrate în zona obișnuită de `storage`; valorile lor sunt incluse în bytecode.

Tipurile de referință sunt organizate astfel, unde `p` este slotul atribuit variabilei:

- **Tablouri dinamice:** slotul `p` conține lungimea tabloului, iar elementele sunt stocate consecutiv începând de la slotul `keccak256(p)`. Elementul `i` al unui tablou de structuri care ocupă `n` sloturi începe la slotul `keccak256(p) + i * n`. Elementele care ocupă cel mult 16 octeți pot fi grupate mai multe în același slot, conform regulilor de stocare.
- **`mapping`:** slotul `p` rămâne rezervat, dar nu conține valoarea asociată unei chei. Pentru cheia `k`, valoarea este stocată la `keccak256(h(k) . p)`, unde `h(k)` este cheia completată la 32 de octeți, iar `.` reprezintă concatenarea. Dacă valoarea este o structură, câmpurile ei ocupă sloturile următoare. Un `mapping` nu poate fi parcurs și nici șters integral dintr-o singură operație, deoarece contractul nu ține evidența tuturor cheilor folosite.
- **`string` și `bytes`:** o valoare de cel mult 31 de octeți este stocată chiar în slotul `p`: datele se află în octeții superiori, iar ultimul octet conține `2 * length`. Pentru valori mai lungi, slotul `p` conține `2 * length + 1`, iar datele încep de la slotul `keccak256(p)`.

Poți afișa organizarea aleasă de compilator cu `forge inspect <Contract> storageLayout`. Deoarece sloturile depind de ordinea declarațiilor, reordonarea sau inserarea unor variabile de stare poate schimba sloturile variabilelor declarate ulterior. Acest lucru contează atunci când citești direct din storage (Pasul 2) sau când lucrezi cu contracte actualizabile (*upgradeable*).

### Stocarea contractelor conectate

După Exercițiul 1, `FidelityPoints` păstrează o referință la catalog (`ICatalog public catalog`), iar `Catalog` păstrează adresa programului de fidelitate (`address fidelityProgram`). Dacă noile variabile sunt declarate după cele existente, organizarea stocării celor două contracte este următoarea:

| Slot în `FidelityPoints` | Variabilă | Conținut |
|---|---|---|
| 0 | `admin` | adresa administratorului (20 de octeți) |
| 1 | `pointValue` | `uint256` |
| 2 | `points` | slot rezervat; `points[client]` se află la `keccak256(client . 2)` |
| 3 | `totalPoints` | `uint256` |
| 4 | `catalog` | adresa contractului `Catalog` (20 de octeți) |

| Slot în `Catalog` | Variabilă | Conținut |
|---|---|---|
| 0 | `products` | lungimea tabloului; elementele încep la `keccak256(0)`, câte 5 sloturi pentru fiecare `Product` |
| 1–4 | `generalPromo` | `state`, `start`, `end`, `percent` |
| 5 | `admin` | adresa administratorului (20 de octeți) |
| 6 | `productPromos` | slot rezervat; `Promo` pentru `code` începe la `keccak256(code . 6)` |
| 7 | `fidelityProgram` | adresa contractului `FidelityPoints` (20 de octeți) |

De reținut:

- **Fiecare contract are propria zonă de storage.** Slotul 0 din `FidelityPoints` și slotul 0 din `Catalog` sunt locații diferite, aparținând unor adrese de contract diferite. Un contract nu poate citi sau modifica direct storage-ul altui contract. `FidelityPoints` află prețul produsului doar prin apelul funcției `getPrice`, iar stocul este modificat de codul din `Catalog` când `FidelityPoints` apelează `decreaseStock`. În acel apel, codul lui `Catalog` rulează în contextul lui `Catalog`, citește și modifică storage-ul acestuia, iar valoarea `msg.sender` este adresa contractului `FidelityPoints`.
- **Interfața nu ocupă storage.** `interface ICatalog` descrie doar funcțiile disponibile pentru apel; nu generează cod executabil sau stare. O variabilă de tip `ICatalog` este stocată la fel ca o variabilă `address`, adică ocupă 20 de octeți; în exemplu, ea se află în slotul 4. Tipul îi permite compilatorului să verifice și să codifice corect apelurile.
- **Conectarea contractelor se realizează prin două adrese.** Legătura este reprezentată de slotul 4 din `FidelityPoints` și slotul 7 din `Catalog`, configurate prin `setCatalog` și `setFidelityProgram`. Poți verifica valorile cu `cast storage $FP 4` și `cast storage $CAT 7`. Fiecare slot conține adresa celuilalt contract, completată cu zerouri până la 32 de octeți.
- **Gruparea depinde de ordinea declarațiilor.** Variabila `catalog` (20 de octeți) este declarată după `totalPoints`, care ocupă un slot întreg, deci `catalog` începe într-un slot nou. Nici nu ar putea fi grupată cu `admin`, deoarece 20 + 20 de octeți depășesc capacitatea de 32 de octeți a unui slot. În schimb, o variabilă mică precum `bool paused` (Exercițiul 3), declarată imediat după `admin`, ar putea împărți slotul 0 cu acesta, deplasând sloturile variabilelor următoare.
- **O răscumpărare accesează storage-ul ambelor contracte.** În `FidelityPoints`, `redeem` citește `catalog`, `pointValue`, `points[client]` și `totalPoints`, iar ultimele două valori sunt modificate. Prin apelurile `getPrice` și `decreaseStock`, funcția accesează în `Catalog` lungimea tabloului `products`, codul fiecărui produs verificat de `findProduct`, prețul, cele două promoții, `admin` și `fidelityProgram`; apoi modifică `stock` și `inStock`. Prima accesare a unui slot într-o tranzacție este, de regulă, una „rece” (*cold*). De aceea, costul unei răscumpărări depinde în mare măsură de numărul sloturilor distincte accesate, după cum se vede în secțiunea următoare.

### Costurile de gas

Fiecare instrucțiune executată de EVM consumă **gas**. Taxa unei tranzacții este `gasUsed × effectiveGasPrice`. Prețul efectiv per unitate de gas include taxa de bază a blocului, care este eliminată din circulație, și taxa de prioritate destinată validatorului [10]. Limita de gas este valoarea maximă stabilită de expeditor pentru tranzacție. Dacă limita este depășită, tranzacția eșuează, însă gas-ul consumat până la acel moment este plătit în continuare.

Tabelul rezumă costurile operațiilor care contribuie cel mai mult la consumul de gas pentru contracte de tipul celor din acest laborator [11, 12, 13]. Un slot sau o adresă este considerată **cold** la prima accesare dintr-o tranzacție și **warm** la accesările ulterioare din aceeași tranzacție.

| Operație | Gas | Explicații |
|---|---|---|
| Costul de bază al unei tranzacții | 21.000 | Este plătit de fiecare tranzacție înainte de executarea codului și acoperă verificarea semnăturii și actualizarea nonce-ului și soldului expeditorului. Pentru un transfer simplu de ether, acesta este costul de bază; de aceea, gruparea mai multor operații într-o tranzacție poate fi mai ieftină. |
| `calldata` | 4 pentru fiecare octet zero, 16 pentru fiecare octet nenul | Conține argumentele apelului (`msg.data`), trimise odată cu tranzacția și păstrate în istoricul blockchainului. Octeții zero sunt mai ieftini; de aceea, un cod `bytes32` completat cu zerouri poate costa mai puțin decât ar sugera cei 32 de octeți ai săi. Începând cu actualizarea Pectra (EIP-7623), tranzacțiile formate în principal din date au un cost minim mai mare per octet. |
| `SLOAD`: citirea unui slot din storage | 2.100 cold, 100 warm | Citește un slot de 32 de octeți din storage-ul contractului, de exemplu `pointValue` sau `points[client]`. Costul cold reflectă accesul la baza de date a stării nodului; după prima accesare, slotul rămâne încărcat pentru restul tranzacției. |
| `SSTORE`: zero → nenul | 20.000 (+ 2.100 dacă slotul este cold) | Creează o intrare nouă în starea persistentă pe care fiecare nod trebuie să o păstreze, de exemplu primele puncte ale unui client sau un produs nou. Este una dintre cele mai costisitoare operații uzuale. |
| `SSTORE`: nenul → altă valoare nenulă | 2.900 (+ 2.100 dacă slotul este cold) | Actualizează o intrare existentă, de exemplu atunci când se adaugă puncte unui client care are deja puncte; dimensiunea stării nu se mărește. |
| `SSTORE`: nenul → zero | 2.900 (+ 2.100 dacă slotul este cold), cu o rambursare de 4.800 | Șterge o intrare, de exemplu prin `delete` sau când un client își cheltuiește toate punctele. Rambursarea recompensează eliberarea stării persistente; se aplică la finalul tranzacției și poate acoperi cel mult o cincime din gas-ul consumat. |
| `SSTORE`: slot modificat deja în aceeași tranzacție | 100 | Slotul a fost deja modificat în tranzacție, astfel încât se actualizează doar valoarea păstrată temporar; de aceea, modificarea câmpurilor grupate sau incrementarea repetată a aceluiași contor poate fi mai ieftină. |
| Citirea unei variabile `constant` sau `immutable` | 3 | Valoarea este inclusă în bytecode și este pusă pe stivă printr-o instrucțiune `PUSH`; nu este accesat storage-ul (vezi explicațiile de mai jos). |
| Apel extern (`CALL`, `STATICCALL`, `DELEGATECALL`) | 2.600 pentru o adresă cold, 100 pentru una warm, plus costul codului executat | Execută codul altui contract, de exemplu `catalog.getPrice(code)` (`STATICCALL`, deoarece funcția este `view`) sau `catalog.decreaseStock(code, quantity)` (`CALL`). Trimiterea de ether cu `CALL` adaugă un cost de 9.000 gas. Argumentele și rezultatele sunt, de asemenea, copiate prin memorie. `DELEGATECALL` are un cost similar, dar o semantică diferită (vezi mai jos). |
| `LOG`: emiterea unui eveniment | 375 + 375 pentru fiecare topic + 8 pentru fiecare octet de date | Scrie o înregistrare în jurnalul tranzacției, de exemplu `PointsRedeemed`. Jurnalele se păstrează în receipt-uri, nu în starea contractului, și nu pot fi citite de contracte; de aceea, sunt mult mai ieftine decât storage-ul. |
| `memory` | 3 pentru fiecare cuvânt de 32 de octeți, plus un termen pătratic pentru zone mari | Zonă temporară pentru variabile locale de tipuri de referință, argumente ale apelurilor externe și valori returnate, de exemplu tabloul construit de `getProducts`. Memoria este eliberată la sfârșitul apelului; termenul pătratic (`words² / 512`) poate face foarte costisitoare construirea unor tablouri foarte mari. |
| Crearea unui contract | 32.000 + 200 pentru fiecare octet de cod publicat | Costul se plătește la publicarea contractului. Costul per octet explică de ce contează dimensiunea bytecode-ului, inclusiv efectul modificatorilor inserați în funcții și al mesajelor text pentru erori. Dimensiunea codului publicat este limitată la 24.576 de octeți (EIP-170). |

**`constant` și `immutable`.** Ambele tipuri de variabile se citesc cu un cost de aproximativ 3 gas, deoarece nu sunt păstrate în storage și nu mai pot fi modificate după publicare [15]. Diferența este **momentul în care valoarea lor devine cunoscută**:

- O variabilă **`constant`** trebuie inițializată chiar în declarație cu o expresie pe care compilatorul o poate evalua, de exemplu `uint constant SECONDS_PER_DAY = 24 * 60 * 60;`. Compilatorul înlocuiește utilizările variabilei cu valoarea ei, care va fi aceeași la fiecare publicare a contractului. Constantele pot avea tipuri de valoare sau tipul `string`.
- O variabilă **`immutable`** primește valoarea **o singură dată, în constructor**. Prin urmare, valoarea poate depinde de argumentele constructorului sau de contextul publicării. De exemplu, se declară `address immutable admin;`, apoi se atribuie `admin = msg.sender;` în constructor. Compilatorul rezervă în bytecode spațiul necesar pentru această valoare, iar constructorul o completează înainte ca acel cod să fie stocat pe blockchain. Publicări diferite pot avea valori diferite. Variabilele `immutable` pot avea doar tipuri de valoare.

În `FidelityPoints`, `admin` poate deveni `immutable` (Exercițiul 7.1), deoarece este stabilit în constructor și nu se schimbă ulterior. Nu poate fi `constant`, fiindcă valoarea nu este cunoscută la compilare. `pointValue` trebuie să rămână o variabilă de stare, deoarece funcția `setPointValue` îi modifică valoarea.

**`DELEGATECALL`.** Costul său de bază este similar cu cel al lui `CALL`, însă semantica este diferită. Prin `DELEGATECALL`, codul contractului apelat se execută **în contextul contractului apelant**: citește și scrie storage-ul apelantului, iar `msg.sender` și `msg.value` păstrează valorile apelului inițial. Dacă `FidelityPoints` ar apela `decreaseStock` prin `DELEGATECALL`, codul din `Catalog` ar interpreta storage-ul lui `FidelityPoints` conform structurii de stocare a lui `Catalog`. Slotul 0, care conține `admin` în `FidelityPoints`, ar fi interpretat ca lungimea tabloului `products`; căutarea produselor s-ar face în sloturi nepotrivite, iar scrierile ar modifica storage-ul lui `FidelityPoints`, nu catalogul. `DELEGATECALL` este folosit intenționat de contracte proxy, care păstrează starea și delegă logica unui contract de implementare ce poate fi înlocuit, precum și de biblioteci cu funcții `external`. În ambele cazuri, contractele trebuie să aibă **organizări compatibile ale stocării**.

Din tabel rezultă câteva concluzii importante:

- **Scrierile în storage domină consumul de gas.** Adăugarea unui produs poate scrie cel puțin cinci sloturi noi, ceea ce înseamnă peste 100.000 gas, în timp ce adunarea a două numere costă aproximativ 3 gas la nivelul instrucțiunii aritmetice.
- **Golirea unui slot poate primi o rambursare de gas**, care poate acoperi cel mult o cincime din consumul tranzacției. Prin urmare, ștergerea datelor care nu mai sunt necesare (cu `delete` sau atribuind zero) poate reduce costul, în limitele regulilor de rambursare.
- **Parcurgerea tablourilor din storage poate fi costisitoare și nu are o limită fixă.** Funcția `findProduct` din `Catalog` citește câte un slot cold (2.100 gas) pentru fiecare produs verificat, deci costul lui `decreaseStock` crește liniar odată cu numărul produselor. Conform EIP-7825, după actualizarea Fusaka (decembrie 2025), limita de gas pentru o tranzacție este de 2²⁴ = 16.777.216 [14]. O funcție al cărei cost crește odată cu dimensiunea tabloului poate deveni imposibil de executat când tabloul este suficient de mare.
- **Copierea datelor nu este gratuită.** Instrucțiunea `Product memory p = products[i]` citește toate sloturile structurii, inclusiv descrierea. În schimb, `Product storage p = products[i]`, urmat de accesarea `p.stock`, permite citirea câmpului necesar fără a copia întreaga structură.
- **Evenimentele costă mult mai puțin decât storage-ul.** Înregistrarea unei răscumpărări într-un eveniment cu trei `topics` și 64 de octeți de date costă aproximativ 2.000 gas. Stocarea acelorași informații într-o structură nouă dintr-un tablou poate costa peste 80.000 gas.

### Optimizarea consumului de gas

Următoarele tehnici sunt folosite frecvent pentru a reduce consumul de gas al unui contract. Efectul fiecărei modificări trebuie **măsurat** (Pasul 5), deoarece rezultatul nu este întotdeauna cel așteptat. Optimizările trebuie evaluate și în raport cu lizibilitatea și siguranța codului.

- **Evită citirea repetată a aceleiași variabile din storage.** Copiază într-o variabilă locală valoarea folosită de mai multe ori, de exemplu `uint balance = points[msg.sender];`, apoi scrie rezultatul în storage o singură dată, la final. Într-o buclă, salvează `products.length` într-o variabilă înainte de a începe parcurgerea.
- **Grupează variabilele asociate.** Pentru valori care sunt citite și scrise împreună, poți folosi tipuri mai mici (`uint128`, `uint64`, `uint40`, `uint8`) și le poți declara consecutiv, astfel încât să împartă un slot. Atenție: conversia explicită la un tip mai mic, precum `uint128(price)`, poate **trunchia valoarea fără să genereze automat o eroare** [22]. Verifică înainte că valoarea se află în intervalul acceptat.
- **Folosește `constant` și `immutable`** pentru valori care nu se schimbă după publicare: `constant` se stabilește la compilare, iar `immutable` în constructor [15]. Citirea lor evită accesul la storage; tabelul de mai sus prezintă costul orientativ.
- **Nu stoca informații care pot fi calculate sau înregistrate prin evenimente.** De exemplu, câmpul `inStock` poate fi dedus din expresia `stock > 0`, iar istoricul operațiilor poate fi înregistrat în evenimente.
- **Preferă `mapping` pentru căutări după cheie.** Găsirea unui element într-un tablou prin parcurgere poate necesita O(n) citiri; un `mapping` permite accesul direct după cheie. Dacă ai nevoie și să enumeri elementele, poți păstra împreună un tablou și un `mapping` care asociază cheia cu indexul.
- **Grupează operațiile într-o singură tranzacție când este potrivit.** Fiecare tranzacție plătește costul de bază de 21.000 gas, iar un slot este cold doar la prima accesare din tranzacția respectivă. O funcție de lot, precum `addPointsBatch`, care actualizează variabila comună `totalPoints` o singură dată, după buclă, poate reduce ambele tipuri de cost.
- **Folosește `calldata` pentru parametrii de tip tablou sau șir care sunt doar citiți de funcții externe**, erori personalizate în locul mesajelor text și blocuri `unchecked { ... }` numai pentru operații despre care poți demonstra că nu pot depăși limitele tipului (de exemplu, o scădere precedată de o verificare explicită). Începând cu Solidity 0.8.22, compilatorul elimină automat verificarea de overflow pentru contorul unor bucle `for` simple.
- **Activează optimizatorul.** Optimizatorul Solidity se configurează în `foundry.toml` prin `optimizer = true` și `optimizer_runs = <n>` [16]. Parametrul `runs` estimează de câte ori vor fi executate funcțiile: o valoare mică favorizează un bytecode mai compact (publicare mai ieftină), iar o valoare mare poate favoriza execuția mai ieftină.


## Partea practică

### Pasul 1: Configurarea proiectului

Creează un proiect Foundry nou și copiază în el soluțiile din Laboratorul 3. Redenumește fișierele și contractele după cum urmează:

```bash
forge init fidelity-shop
cd fidelity-shop
rm src/Counter.sol test/Counter.t.sol script/Counter.s.sol
cp <path to lab4>/src/FidelityPointsFinal.sol src/FidelityPoints.sol
cp <path to lab4>/src/CatalogFinal.sol src/Catalog.sol
sed -i 's/contract FidelityPointsFinal/contract FidelityPoints/' src/FidelityPoints.sol
sed -i 's/contract CatalogFinal/contract Catalog/' src/Catalog.sol
forge build
```

Citește ambele contracte și identifică elementele realizate în Laboratorul 3: modificatorul `onlyAdmin` și eroarea `NotAdmin`, variabila `totalPoints` și funcția `internal` care o actualizează, câmpul `stock` și funcțiile care îl modifică, `mapping`-ul `productPromos`, funcția `getProducts` și funcția `pure` `discountedPrice`. Funcția `getPrice` returnează prețul produsului după aplicarea celei mai avantajoase promoții active și va fi folosită în Exercițiul 1.

În primul terminal, pornește `anvil`. În al doilea terminal, setează variabilele folosite în Laboratorul 3:

```bash
export ETH_RPC_URL=http://127.0.0.1:8545
ANVIL_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80   # anvil account 0
CLIENT=0x70997970C51812dc3A010C7d01b50e0d17dc79C8                              # anvil account 1
CLIENT_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
```

### Pasul 2: Inspectarea organizării stocării

Afișează organizarea stocării contractului `Catalog` [17]:

```bash
forge inspect Catalog storageLayout
```

| Nume | Tip | Slot |
|---|---|---|
| `products` | `struct Catalog.Product[]` | 0 |
| `generalPromo` | `struct Catalog.Promo` | 1 |
| `admin` | `address` | 5 |
| `productPromos` | `mapping(bytes32 => struct Catalog.Promo)` | 6 |

`generalPromo` ocupă sloturile 1–4, deoarece structura `Promo` are patru câmpuri care ocupă fiecare câte un slot. De aceea, `admin` începe la slotul 5.

Publică contractul `Catalog` și adaugă două produse:

```bash
forge create src/Catalog.sol:Catalog --private-key $ANVIL_KEY --broadcast
CAT=<deployed contract address>
cast send $CAT "addProduct(bytes32,string,uint256,uint256)" \
  $(cast format-bytes32-string "P001") "Coffee mug" 50 10 --private-key $ANVIL_KEY
cast send $CAT "addProduct(bytes32,string,uint256,uint256)" \
  $(cast format-bytes32-string "P002") "T-shirt" 100 5 --private-key $ANVIL_KEY
```

Slotul 0 conține lungimea tabloului. Elementele încep la slotul `keccak256(0)`, iar fiecare `Product` ocupă 5 sloturi. Numerele sloturilor sunt întregi pe 256 de biți; pentru a aduna offset-uri la o astfel de valoare, exemplul folosește o mică funcție ajutătoare scrisă în Python:

```bash
cast storage $CAT 0                                   # lungimea tabloului products: 2
BASE=$(cast keccak $(cast to-uint256 0))              # primul slot al products[0]
slot() { python3 -c "print(hex(int('$1', 16) + $2))"; }
cast storage $CAT $BASE                               # codul products[0]
cast storage $CAT $(slot $BASE 1)                     # descrierea products[0]
cast --to-dec $(cast storage $CAT $(slot $BASE 7))    # prețul products[1] = BASE + 5*1 + 2
```

Descrierea `"Coffee mug"` are 10 octeți, deci este stocată în slotul câmpului. Textul ocupă octeții superiori, iar ultimul octet conține `0x14`, adică `2 × 10`.

Activează o promoție pentru `P001` și localizeaz-o în `mapping`-ul `productPromos` (slotul 6). Structura începe la slotul calculat cu `cast index`, iar câmpul `percent` este al patrulea:

```bash
cast send $CAT "startProductPromo(bytes32,uint256,uint256)" \
  $(cast format-bytes32-string "P001") 7 20 --private-key $ANVIL_KEY
PROMO=$(cast index bytes32 $(cast format-bytes32-string "P001") 6)
cast --to-dec $(cast storage $CAT $(slot $PROMO 3))   # percent: 20
```

### Pasul 3: Măsurarea consumului de gas al tranzacțiilor

Publică `FidelityPoints` și acordă puncte de trei ori: de două ori aceluiași client și o dată unui client nou. După fiecare tranzacție, afișează cantitatea de gas consumată:

```bash
forge create src/FidelityPoints.sol:FidelityPoints \
  --private-key $ANVIL_KEY --broadcast --constructor-args 10
FP=<deployed contract address>
CLIENT2=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC                              # anvil account 2

cast send $FP "addPoints(address,uint256)" $CLIENT 100 --private-key $ANVIL_KEY | grep gasUsed
cast send $FP "addPoints(address,uint256)" $CLIENT 100 --private-key $ANVIL_KEY | grep gasUsed
cast send $FP "addPoints(address,uint256)" $CLIENT2 100 --private-key $ANVIL_KEY | grep gasUsed
```

Rezultatele sunt aproximativ următoarele:

| Tranzacție | Gas consumat | `points[client]` | `totalPoints` |
|---|---|---|---|
| Primul apel `addPoints` pentru `CLIENT` | 69,201 | 0 → 100 | 0 → 100 |
| Al doilea apel `addPoints` pentru `CLIENT` | 35,001 | 100 → 200 | 100 → 200 |
| Primul apel `addPoints` pentru `CLIENT2` | 52,089 | 0 → 100 | 200 → 300 |

Aceeași funcție, cu același cod, poate consuma cantități foarte diferite de gas. Diferența dintre primele două tranzacții, de 34.200 gas, este egală cu `2 × (20.000 − 2.900)`: în prima tranzacție, ambele sloturi trec de la zero la o valoare nenulă. În a treia tranzacție, doar slotul clientului nou trece de la zero la o valoare nenulă.

Folosind tabelul costurilor de gas, explică de ce cheltuirea **tuturor** punctelor unui client poate costa cu aproximativ 4.800 gas mai puțin decât cheltuirea unei părți din puncte. Verifică prin trimiterea a două tranzacții `spendPoints(100)` din contul `CLIENT`.

Consumul de gas poate fi estimat și înainte de trimiterea tranzacției, folosind `cast estimate`, care primește aceiași parametri ca `cast send`:

```bash
cast estimate $FP "addPoints(address,uint256)" $CLIENT 100 --from $(cast wallet address --private-key $ANVIL_KEY)
```

### Pasul 4: Tranzacții eșuate și datele erorilor

Apelează `addPoints` din contul clientului:

```bash
cast send $FP "addPoints(address,uint256)" $CLIENT 1 --private-key $CLIENT_KEY
```

Mai întâi, `cast` estimează gas-ul tranzacției. Deoarece estimarea se încheie cu `revert`, tranzacția nu este trimisă, iar `cast` afișează datele erorii. Primii patru octeți, `0x17a84242`, reprezintă selectorul erorii, urmat de adresa apelantului:

```bash
cast sig "NotAdmin(address)"
cast decode-error <error data> --sig "NotAdmin(address)"
```

Acum forțează trimiterea tranzacției specificând explicit limita de gas; astfel, nu se mai face estimarea obișnuită înainte de trimitere:

```bash
cast send $FP "addPoints(address,uint256)" $CLIENT 1 --private-key $CLIENT_KEY --gas-limit 100000
```

Receipt-ul arată `status 0 (failed)`: tranzacția a fost inclusă într-un bloc, iar clientul a plătit gas-ul consumat (aproximativ 24.700), deși starea contractului nu s-a modificat.

### Pasul 5: Măsurarea consumului de gas în teste

Foundry/Forge oferă mai multe instrumente pentru măsurarea consumului de gas [18, 19]:

```bash
forge test --gas-report              # gas per funcție: minim, medie, mediană, maxim
forge snapshot                       # scrie consumul de gas al fiecărui test în .gas-snapshot
forge snapshot --diff                # compară consumul curent cu .gas-snapshot
forge build --sizes                  # dimensiunea bytecode-ului fiecărui contract
```

Fluxul obișnuit pentru o optimizare este următorul: rulează `forge snapshot` înainte de modificare, schimbă codul, apoi rulează `forge snapshot --diff` pentru a vedea efectul schimbării asupra fiecărui test.

În cadrul unui test, apelurile sunt executate în aceeași tranzacție de testare. Prin urmare, sloturile accesate de `setUp` sau de apelurile precedente sunt deja warm, iar consumul afișat poate fi mai mic decât într-o tranzacție separată pe rețea. Opțiunea `--isolate` execută fiecare apel de nivel superior într-o tranzacție separată și oferă valori mai apropiate de cele observate la Pasul 3. Poți măsura un anumit apel folosind cheatcode-urile `vm.startSnapshotGas` și `vm.stopSnapshotGas`:

```solidity
function test_GasAddPoints() public {
    vm.startSnapshotGas("addPoints");
    fp.addPoints(client, 100);
    uint gasUsed = vm.stopSnapshotGas();
    emit log_named_uint("addPoints gas", gasUsed);
}
```

Rulează `forge test --match-test test_GasAddPoints -vv --isolate` și compară rezultatul cu cel de la Pasul 3. Valoarea măsurată nu include costul de bază de 21.000 gas și costul pentru `calldata`, plătite de fiecare tranzacție.

### Pasul 6: Interacțiunea dintre contracte și propagarea erorilor

Acest pas ilustrează ce se întâmplă cu starea a două contracte atunci când contractul apelat execută `revert`, mai întâi fără `try`/`catch`, apoi cu această instrucțiune [2, 3]. Contractul `A` conține variabila de stare `int a`, iar contractul `B` conține `int b` și apelează contractul `A`. Ambele sunt definite în fișierul `ContractInteraction.sol`; copiază fișierul în proiect:

```bash
cp <path to lab4>/src/ContractInteraction.sol src/
```

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.36;

contract A {
    int public a;

    error NegativeValue(int value);

    function setA(int value) external returns (int) {
        a = value;                                     // modified before the checks
        if (value < 0) revert NegativeValue(value);    // custom error
        require(value != 13, "Unlucky value");         // eroare de tip Error(string)
        return 100 / (value - 10);                     // Panic(0x12) dacă value == 10
    }
}

contract B {
    A public contractA;
    int public b;

    uint public nbCalls;
    uint public nbCallsError;
    uint public nbCallsPanic;
    uint public nbCallsRevert;

    constructor(A _contractA) {
        contractA = _contractA;
    }

    function setDirect(int value) external {
        b = value;
        contractA.setA(value);                         // an error in A bubbles up
    }

    function setWithTry(int value) external {
        b = value;
        nbCalls += 1;
        try contractA.setA(value) returns (int result) {
            b = result;
        } catch Error(string memory) {
            nbCallsError += 1;
        } catch Panic(uint) {
            nbCallsPanic += 1;
        } catch (bytes memory) {
            nbCallsRevert += 1;
        }
    }
}
```

Funcția `A.setA` modifică `a` **înainte** să verifice argumentul, pentru a putea observa dacă modificarea supraviețuiește unui `revert`. Funcția poate eșua în trei moduri: declanșează eroarea personalizată `NegativeValue` pentru o valoare negativă, `Error(string)` pentru valoarea 13 și `Panic(0x12)` — împărțire la zero — pentru valoarea 10.

Publică mai întâi contractul `A`, apoi contractul `B`, transmițând adresa lui `A` ca argument al constructorului lui `B`. Definește și o funcție shell care afișează starea ambelor contracte:

```bash
forge create src/ContractInteraction.sol:A --private-key $ANVIL_KEY --broadcast
A=<deployed contract address>
forge create src/ContractInteraction.sol:B --private-key $ANVIL_KEY --broadcast --constructor-args $A
B=<deployed contract address>
state() {
  echo "a=$(cast call $A 'a()(int256)') b=$(cast call $B 'b()(int256)')" \
       "error=$(cast call $B 'nbCallsError()(uint256)') panic=$(cast call $B 'nbCallsPanic()(uint256)')" \
       "revert=$(cast call $B 'nbCallsRevert()(uint256)')"
}
cast send $B "setDirect(int256)" 5 --private-key $ANVIL_KEY
state                                                   # a=5 b=5
```

**Scenariul 1: `B` apelează direct `A`, iar `A` execută `revert`.** Apelează `setDirect` cu o valoare negativă. `cast` ar putea interpreta numărul negativ ca pe o opțiune, de aceea opțiunile sunt plasate înaintea argumentelor, iar argumentele negative după `--`:

```bash
cast send --private-key $ANVIL_KEY $B "setDirect(int256)" -- -7
cast send --private-key $ANVIL_KEY $B "setDirect(int256)" 13
state                                                   # a=5 b=5
```

Ambele apeluri eșuează. Deși tranzacția a fost trimisă către `B`, `cast` afișează eroarea produsă în `A` (`NegativeValue(-7)`, respectiv `Error("Unlucky value")`): eroarea s-a **propagat** din `A` prin `B` până la apelant. Atât `a`, cât și `b` rămân egale cu 5. Instrucțiunile `b = value` din `B` și `a = value` din `A` au fost executate, dar `revert` a anulat toate modificările făcute de tranzacție în ambele contracte. Pentru a observa acest lucru pe blockchain, nu doar în timpul estimării gas-ului, repetă primul apel cu `--gas-limit 200000`. Tranzacția va fi inclusă într-un bloc cu `status 0 (failed)`, dar starea va rămâne neschimbată.

**Scenariul 2: `B` apelează `A` folosind `try`/`catch`, iar `A` execută `revert`.** Apelează `setWithTry` cu fiecare dintre valorile care provoacă eșecul lui `A`, apoi cu o valoare validă:

```bash
cast send --private-key $ANVIL_KEY $B "setWithTry(int256)" -- -7
state                                                   # a=5 b=-7  revert=1
cast send --private-key $ANVIL_KEY $B "setWithTry(int256)" 13
state                                                   # a=5 b=13  error=1
cast send --private-key $ANVIL_KEY $B "setWithTry(int256)" 10
state                                                   # a=5 b=10  panic=1
cast send --private-key $ANVIL_KEY $B "setWithTry(int256)" 20
state                                                   # a=20 b=10
```

De această dată, tranzacțiile se încheie cu succes. Când `A` execută `revert`, sunt anulate doar modificările făcute **în interiorul apelului către `A`**, astfel încât `a` își păstrează valoarea anterioară. Contractul `B` prinde eroarea și continuă execuția, deci propriile sale modificări se păstrează: `b` primește noua valoare, iar contorul corespunzător clauzei `catch` este incrementat. Eroarea personalizată `NegativeValue` ajunge în clauza generală `catch (bytes memory)`, deoarece Solidity nu are o clauză `catch` dedicată unei erori personalizate. La ultimul apel, `A` reușește și returnează `100 / (20 − 10) = 10`, iar `B` salvează rezultatul în `b`.

Traseul de execuție al unei tranzacții arată apelurile interne și locul în care a apărut un `revert`:

```bash
cast run <transactionHash>
```

Pentru apelul cu valoarea 10, traseul arată că apelul `setA(10)` se termină cu `[Revert] panic: division or modulo by zero (0x12)`, în timp ce tranzacția exterioară se încheie normal.

Tabelul rezumă cele două scenarii:

| `A` execută `revert`, iar… | `a` | `b` | Tranzacție | Eroarea primită de apelant |
|---|---|---|---|---|
| `B` apelează direct `A` | neschimbat | neschimbat | eșuată | eroarea produsă de `A` |
| `B` apelează `A` prin `try`/`catch` | neschimbat | actualizat | reușită | niciuna; `B` gestionează eroarea |

Observă că, în Scenariul 2, gas-ul consumat de `A` înainte de `revert` este plătit în continuare, chiar dacă tranzacția exterioară reușește. Același mecanism este folosit în Exercițiul 1.6: `redeem` prinde eșecul apelului `Catalog.decreaseStock`, restituie punctele clientului și înregistrează eșecul, în loc să anuleze întreaga răscumpărare.

## Exerciții

### Exercițiul 1: Cumpărarea produselor din catalog cu puncte

Cele două contracte sunt conectate astfel încât un client să poată cumpăra produse folosind punctele acumulate. Prețul produsului este exprimat în aceeași unitate ca valoarea punctelor: un client cu `n` puncte poate cumpăra produse cu valoarea totală de cel mult `n * pointValue`.

1. În `FidelityPoints.sol`, declară interfața `ICatalog` prezentată în secțiunea *Interacțiunea dintre contracte*, variabila de stare `ICatalog public catalog` și funcția `setCatalog(address)`, accesibilă doar administratorului.
2. Adaugă funcția `redeem(bytes32 code, uint quantity)`, care trebuie să:
   - obțină prețul curent al produsului din catalog prin `getPrice` și să calculeze numărul necesar de puncte prin **rotunjire în sus** (`(cost + pointValue - 1) / pointValue`), astfel încât magazinul să nu piardă valoare din cauza rotunjirii;
   - declanșeze `error InsufficientPoints(uint required, uint available)` dacă clientul nu are suficiente puncte și o eroare personalizată dacă adresa catalogului nu a fost configurată sau dacă `quantity` este zero;
   - scadă punctele din soldul clientului și din `totalPoints`, apoi să apeleze `decreaseStock` în catalog, respectând ordinea **checks–effects–interactions**.
3. În `Catalog.sol`, funcția `decreaseStock` poate fi apelată în prezent de oricine. Adaugă variabila de stare `fidelityProgram`, configurată de administrator prin `setFidelityProgram(address)`, precum și un modificator care permite apelarea lui `decreaseStock` numai de către administrator sau programul de fidelitate. Ce adresă vede `Catalog` în `msg.sender` atunci când clientul apelează `redeem`? De ce nu trebuie folosit `tx.origin` pentru autorizare?
4. Publică ambele contracte pe `anvil`, configurează legătura în ambele direcții, adaugă un produs, acordă puncte clientului și cumpără produsul din contul clientului:

   ```bash
   cast send $FP "setCatalog(address)" $CAT --private-key $ANVIL_KEY
   cast send $CAT "setFidelityProgram(address)" $FP --private-key $ANVIL_KEY
   cast send $FP "redeem(bytes32,uint256)" $(cast format-bytes32-string "P001") 2 --private-key $CLIENT_KEY
   ```

   Verifică soldul de puncte al clientului, valoarea returnată de `getTotalPoints()` și stocul produsului. Activează o promoție pentru produs și verifică dacă următoarea cumpărare necesită mai puține puncte.
5. Apelează `redeem` folosind codul unui produs inexistent. În `Catalog` apare eroarea `ProductNotFound`. Ce eroare primește clientul și de ce?
6. Modifică `redeem` astfel încât eșecul apelului `decreaseStock` să **nu** anuleze întreaga tranzacție: încadrează apelul în `try`/`catch`, restituie punctele clientului și ajustează `totalPoints`, returnează `false` și numără eșecurile în trei contoare publice — câte unul pentru `Error(string)`, `Panic(uint)` și clauza generală `bytes`. Provoacă fiecare tip de eroare (indicii: apel înainte de configurarea lui `setFidelityProgram`, dacă modificatorul folosește `require` cu mesaj; cantitate mai mare decât stocul; eroare personalizată în modificator) și verifică valorile contoarelor. Explică de ce contoarele ar rămâne la zero dacă `redeem` ar declanșa un `revert` după clauza `catch`.

### Exercițiul 2: Evenimente

1. Adaugă următoarele evenimente în `FidelityPoints` și emite-le în funcțiile corespunzătoare:
   - `PointsAdded(address indexed client, uint amount)`
   - `PointsSpent(address indexed client, uint amount)`
   - `PointValueChanged(uint oldValue, uint newValue)`
   - `PointsRedeemed(address indexed client, bytes32 indexed code, uint quantity, uint pointsSpent)`
   - `RedemptionFailed(address indexed client, bytes32 indexed code, bytes reason)`
2. Adaugă în `Catalog` evenimentele `ProductAdded(bytes32 indexed code, uint price, uint stock)`, `StockChanged(bytes32 indexed code, uint newStock)` și `PromoStarted(bytes32 indexed code, uint end, uint percent)`. Pentru promoția generală, folosește codul `bytes32(0)`.
3. Repetă scenariul de la Exercițiul 1.4 și extrage evenimentele cu `cast logs` [21]. Filtrează evenimentele `PointsRedeemed` pentru un anumit client și compară primul `topic` al unei înregistrări cu rezultatul comenzii `cast sig-event`:

   ```bash
   cast logs --from-block 0 --address $FP "PointsAdded(address indexed client, uint256 amount)"
   cast logs --from-block 0 --address $FP "PointsRedeemed(address indexed, bytes32 indexed, uint256, uint256)" $CLIENT
   cast sig-event "PointsRedeemed(address,bytes32,uint256,uint256)"
   ```

   În receipt-ul unei tranzacții `redeem` (comanda `cast receipt`), identifică jurnalele emise de fiecare dintre cele două contracte.
4. Magazinul dorește să păstreze istoricul tuturor cumpărăturilor. Compară două variante: un tablou `Redemption[]` în storage, unde `Redemption` conține clientul, codul produsului, cantitatea și punctele cheltuite, și evenimentul `PointsRedeemed`. Estimează consumul de gas pentru fiecare variantă folosind tabelul de costuri și verifică estimarea cu `forge test --gas-report`. În ce situație este necesar să păstrezi istoricul în storage?

### Exercițiul 3: Modificatori și erori

1. Adaugă în `FidelityPoints` variabila de stare `bool public paused` și funcțiile `pause()` și `unpause()`, accesibile doar administratorului. Scrie modificatorii `whenNotPaused` și `whenPaused` sau un singur modificator cu argument, `whenPaused(bool expected)`. Cât timp programul este suspendat, nu se pot adăuga, cheltui sau răscumpăra puncte; valoarea unui punct poate fi schimbată **numai** cât timp programul este suspendat.
2. Scrie modificatorul cu argument `validAmount(uint amount)`, care declanșează o eroare personalizată dacă suma este zero, și aplică-l funcțiilor `addPoints`, `spendPoints` și `redeem`.
3. Aplică mai mulți modificatori funcției `addPoints`, de exemplu `onlyAdmin whenNotPaused validAmount(_points)`. Ce eroare primește un client care apelează `addPoints` cât timp programul este suspendat? Schimbă ordinea modificatorilor și repetă apelul. Care ordine este de preferat și de ce?
4. În `spendPoints` și `redeem`, verifică prin `assert` că `totalPoints` nu este mai mic decât soldul clientului după actualizare. De ce este potrivit `assert` aici, în timp ce `require` este potrivit pentru verificarea soldului clientului? Ce date ar returna un `assert` eșuat?
5. Rulează `forge build --sizes`. Mută logica din `onlyAdmin` într-o funcție `internal` numită `_checkAdmin()`, apelată de modificator, apoi compară dimensiunea bytecode-ului și explică diferența.

### Exercițiul 4: Testare

Creează fișierul `test/Redeem.t.sol`. Funcția `setUp` trebuie să publice ambele contracte, să le conecteze, să adauge produse și să acorde puncte unui client:

```solidity
function setUp() public {
    cat = new Catalog();
    fp = new FidelityPoints(10);
    fp.setCatalog(address(cat));
    cat.setFidelityProgram(address(fp));
    cat.addProduct("P001", "Coffee mug", 55, 3);
    fp.addPoints(client, 100);
}
```

Scrie teste care verifică următoarele:

1. o răscumpărare reușită actualizează punctele clientului, `totalPoints` și stocul și emite `PointsRedeemed`. Indiciu [20]: înaintea apelului, folosește `vm.expectEmit(true, true, false, true, address(fp))`, urmat de `emit FidelityPoints.PointsRedeemed(client, "P001", 1, 6)`;
2. numărul de puncte este rotunjit în sus (la un preț de 55 și o valoare a punctului de 10, un produs costă 6 puncte) și o promoție activă reduce numărul necesar;
3. o răscumpărare fără suficiente puncte declanșează `InsufficientPoints(required, available)` cu valorile corecte;
4. un client nu poate apela direct `decreaseStock` în catalog;
5. o răscumpărare pentru o cantitate mai mare decât stocul returnează `false`, restituie punctele și incrementează contorul `Panic`;
6. `addPoints`, `spendPoints` și `redeem` declanșează `revert` cât timp programul este suspendat.

Rulează `forge test --gas-report --isolate` și notează consumul de gas al funcției `redeem`. Cât din acest consum se datorează apelurilor externe către catalog?

### Exercițiul 5: Organizarea stocării și gruparea câmpurilor

1. Folosind metoda de la Pasul 2, citește direct din storage stocul celui de-al doilea produs și data de încheiere a promoției generale. Identifică sloturile pe baza rezultatului `forge inspect`.
2. Rulează `forge snapshot` pentru testele din Exercițiul 4. Apoi grupează câmpurile structurilor din `Catalog` astfel:
   - `Promo`: `State state; uint40 start; uint40 end; uint8 percent;`
   - `Product`: `bytes32 code; string description; uint128 price; uint64 stock; bool inStock;`

   Rulează din nou `forge inspect Catalog storageLayout`. Câte sloturi ocupă acum fiecare structură? Ce variabile de stare și-au schimbat slotul?
3. Rulează `forge snapshot --diff` și explică diferențele pentru `addProduct`, `startProductPromo`, `decreaseStock` și `redeem`. De ce devine `decreaseStock` mai ieftină, deși modifică aceleași două câmpuri?
4. Parametrii funcțiilor `addProduct` și `increaseStock` rămân de tip `uint`. Ce se întâmplă dacă o valoare mai mare decât `type(uint128).max` este convertită prin `uint128(price)`? Adaugă verificările necesare și un test care demonstrează comportamentul.
5. De ce este suficient tipul `uint40` pentru o marcă temporală (*timestamp*)?
6. Câmpul `inStock` este redundant, deoarece poate fi calculat prin `stock > 0`. Elimină-l din structură și măsoară din nou consumul de gas pentru `decreaseStock` și `getProducts`. Ce funcții și teste trebuie modificate?

### Exercițiul 6: Tablouri și `mapping`-uri

1. Scrie un test care adaugă 100 de produse în catalog și măsoară consumul de gas pentru `decreaseStock` (sau `redeem`) la primul și la ultimul produs, folosind `vm.startSnapshotGas` și opțiunea `--isolate`. Explică diferența.
2. Adaugă în `Catalog` un `mapping(bytes32 => uint) productIndex`, care păstrează poziția fiecărui produs **plus unu**. De ce se adaugă unu? Rescrie `findProduct` astfel încât să nu mai conțină o buclă și fă ca `addProduct` să declanșeze o eroare personalizată dacă acel cod există deja. Măsoară din nou gas-ul testului de la punctul 1. Cu cât crește costul lui `addProduct` și după câte apeluri `decreaseStock` asupra ultimului produs se recuperează costul suplimentar?
3. Adaugă funcția `removeProduct(bytes32 code)`, accesibilă doar administratorului, care mută ultimul produs pe poziția produsului eliminat și apoi apelează `pop` (metoda *swap and pop*). Menține corect `productIndex` și șterge promoția produsului eliminat. De ce nu este suficientă instrucțiunea `delete products[i]`? Cum influențează consumul de gas al lui `removeProduct` sloturile setate la zero?
4. Estimează consumul de gas al funcției `getProducts(false, false)` pentru 100 de produse folosind `cast estimate` sau un test. Compară rezultatul cu limita de 16.777.216 gas per tranzacție. Ce s-ar întâmpla dacă `redeem` ar apela `getProducts`? Scrie o variantă `getProducts(uint offset, uint limit)` care returnează cel mult `limit` produse, începând de la poziția `offset`.

### Exercițiul 7: Optimizarea consumului de gas în `FidelityPoints`

Înainte de a începe, rulează `forge snapshot`. Aplică pe rând modificările de mai jos și notează efectul fiecăreia cu `forge snapshot --diff`, într-un tabel cu coloanele *Funcție*, *Gas înainte*, *Gas după* și *Tehnică*.

1. Adresa administratorului nu se schimbă. Declară `admin` ca `immutable` și măsoară consumul de gas al lui `addPoints`. Folosește `forge inspect FidelityPoints storageLayout` pentru a identifica variabilele ale căror sloturi s-au schimbat și explică de ce comenzile `cast storage` din Laboratorul 3 returnează acum valori diferite.
2. În `spendPoints` și `redeem`, citește `points[msg.sender]` o singură dată și salvează valoarea într-o variabilă locală. Înlocuiește scăderea verificată automat cu o verificare explicită, care declanșează `InsufficientPoints`, urmată de scăderea într-un bloc `unchecked`. Explică de ce scăderea nu poate depăși limitele tipului. Este la fel de sigur să scazi din `totalPoints` într-un bloc `unchecked`?
3. Adaugă funcția `addPointsBatch(address[] calldata clients, uint[] calldata amounts)`, accesibilă doar administratorului, care actualizează `totalPoints` o singură dată, după buclă. Compară consumul de gas pentru acordarea punctelor către 10 clienți printr-o singură tranzacție de lot și prin 10 apeluri separate `addPoints` (adaugă 21.000 gas pentru fiecare tranzacție). Apoi înlocuiește `calldata` cu `memory` pentru parametri și măsoară din nou.
4. Într-o copie a contractului, înlocuiește erorile personalizate din `FidelityPoints` cu `require(condition, "message")` și compară dimensiunea bytecode-ului, precum și consumul de gas al unui apel care eșuează cu `revert`.
5. Activează optimizatorul în `foundry.toml` cu `optimizer = true`, apoi compară costul publicării (afișat prin `forge test --gas-report`) și consumul de gas al lui `redeem` pentru `optimizer_runs = 1` și `optimizer_runs = 1000000`.

### Exercițiul 8: Publicarea contractelor pe Sepolia

Publică versiunile finale ale contractelor `Catalog` și `FidelityPoints` pe Sepolia, conform procedurii din Laboratorul 3, apoi conectează-le. Adaugă un produs, acordă puncte la adresa unui coleg și roagă-l să cumpere produsul din propriul cont. În Etherscan [23], deschide tranzacția `redeem` și consultă fila *Logs*: identifică evenimentele emise de fiecare contract și `topics`-urile lor. Compară valoarea `gasUsed` a tranzacției cu cea măsurată pe `anvil` și calculează costul în ether folosind prețul efectiv al gas-ului. Notează în raport adresele contractelor și hash-urile tranzacțiilor.

## Referințe

1. Documentația Solidity, *Modificatori de funcții*. https://docs.soliditylang.org/en/latest/contracts.html#function-modifiers
2. Documentația Solidity, *Gestionarea erorilor: assert, require, revert și excepții*. https://docs.soliditylang.org/en/latest/control-structures.html#error-handling-assert-require-revert-and-exceptions
3. Documentația Solidity, *try/catch*. https://docs.soliditylang.org/en/latest/control-structures.html#try-catch
4. Documentația Solidity, *Evenimente*. https://docs.soliditylang.org/en/latest/contracts.html#events
5. Documentația Solidity, *Specificația ABI a contractelor: evenimente*. https://docs.soliditylang.org/en/latest/abi-spec.html#events
6. Documentația Solidity, *Interfețe*. https://docs.soliditylang.org/en/latest/contracts.html#interfaces
7. Documentația Solidity, *Apeluri externe de funcții*. https://docs.soliditylang.org/en/latest/control-structures.html#external-function-calls
8. Documentația Solidity, *Considerații de securitate: modelul checks-effects-interactions*. https://docs.soliditylang.org/en/latest/security-considerations.html#use-the-checks-effects-interactions-pattern
9. Documentația Solidity, *Organizarea variabilelor de stare în storage*. https://docs.soliditylang.org/en/latest/internals/layout_in_storage.html
10. ethereum.org, *Gas și comisioane*. https://ethereum.org/en/developers/docs/gas/
11. V. Buterin, M. Swende, *EIP-2929: Creșterea costului pentru accesarea stării*. https://eips.ethereum.org/EIPS/eip-2929
12. V. Buterin, M. Swende, *EIP-3529: Reducerea rambursărilor*. https://eips.ethereum.org/EIPS/eip-3529
13. *EVM Codes: referință interactivă pentru opcode-urile EVM și costurile de gas*. https://www.evm.codes/
14. G. Ballet, T. Wahrstätter, *EIP-7825: Limitarea gas-ului per tranzacție*. https://eips.ethereum.org/EIPS/eip-7825
15. Documentația Solidity, *Variabile de stare constant și immutable*. https://docs.soliditylang.org/en/latest/contracts.html#constant-and-immutable-state-variables
16. Documentația Solidity, *Optimizatorul*. https://docs.soliditylang.org/en/latest/internals/optimizer.html
17. Foundry Book, *forge inspect*. https://getfoundry.sh/forge/reference/forge-inspect
18. Foundry Book, *Urmărirea consumului de gas* și *Rapoarte de gas*. https://getfoundry.sh/forge/gas-tracking, https://getfoundry.sh/forge/gas-reports
19. Foundry Book, *Instantanee de gas pentru funcții* și *instantanee de gas pentru secțiuni*. https://getfoundry.sh/forge/gas-function-snapshots, https://getfoundry.sh/forge/gas-section-snapshots
20. Foundry Book, *expectEmit*. https://getfoundry.sh/reference/cheatcodes/expect-emit
21. Foundry Book, *cast logs*. https://getfoundry.sh/cast/reference/logs
22. Documentația Solidity, *Conversii între tipurile elementare*. https://docs.soliditylang.org/en/latest/types.html#conversions-between-elementary-types
23. Etherscan, *Explorer pentru testnet-ul Sepolia*. https://sepolia.etherscan.io/

Resurse suplimentare:

- [Documentația Solidity](https://docs.soliditylang.org/en/latest/) și [versiunea PDF](https://docs.soliditylang.org/_/downloads/en/latest/pdf/)
- [Remix IDE](https://remix.ethereum.org/)
- [Convertor pentru `bytes32`](https://web3-type-converter.onbrn.com/)

> **Notă privind pregătirea documentului.** Unele părți ale acestui ghid de laborator au fost redactate cu ajutorul asistentului AI Claude (Anthropic).
