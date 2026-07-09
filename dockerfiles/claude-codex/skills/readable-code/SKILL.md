---
name: readable-code
description: >-
  コードを書く・レビューする・リファクタするときに適用する、可読性重視の
  コーディング規約。自明なコメントの排除と「目的(why)」コメント、ガード節による
  早期リターン(正常系を浅いインデントへ)、意味のある命名(tmp/buf など汎用名の禁止)、
  複雑なワンライナーの回避を扱う。Go / Python / Rust / TypeScript など言語を問わず適用する。
---

# readable-code

コードの「意図」を最短で読み取れる状態を優先するための規約。
書くとき・レビューするとき・リファクタするときに、以下の原則を適用・指摘する。

これらは特定の流儀ではなく、広く知られた設計原則
(Fowler の *Refactoring*、McConnell の *Code Complete*、Clean Code、Cognitive Complexity)
に沿ったもの。末尾の[参考](#参考)に一次情報を挙げる。

## 使いどころ

- 新しく関数・メソッドを書くとき
- 既存コードをレビュー / リファクタするとき
- 「コメントを足そうとした」「インデントが深くなってきた」「名前に迷った」瞬間

---

## 原則1: 自明なコメントを書かない

コードを読めば分かることをコメントで繰り返さない。実装を更新したときにコメントの更新が
漏れると、**コードとコメントが矛盾**し、無いより有害になる (stale comment)。

インラインコメントを書きたくなったら、それは次のどちらかのサイン:

1. **変数・関数名が不明瞭** → 名前を直す
2. **処理のかたまりに名前を付けたい** → 関数に抽出する

```go
// Bad: コードそのままの説明。実装が変われば即座に嘘になる
// i を 1 増やす
i++

// x が 0 より大きいかチェック
if x > 0 {
    // ユーザーに手数料を加算する
    total = total + x*rate
}
```

```go
// Good: コメントを消し、名前と抽出で意図を語らせる
i++

if hasPositiveBalance(x) {
    total = addTransactionFee(total, x, rate)
}
```

> コメントを消すこと自体が目的ではない。「コメントで補う」代わりに
> 「名前と構造で自明にする」ことが目的。

---

## 原則2: コメントは「目的 (why)」を書く

コメントを残すなら、**その処理が何をしているか (what)** ではなく、
**なぜそうするのか / 何を目的としているのか (why)** を書く。
関数レベルのドキュメントで、処理の目的・背景・制約・トレードオフを説明する。

whatはコードが語る。whyはコードに書けない — だからコメントの出番はそこだけ。

```python
# Bad: 何をしているかの逐語訳 (コードを読めば分かる)
# retries が 3 未満の間ループする
while retries < 3:
    ...
```

```python
# Good: なぜ 3 なのか / 何のためか (コードからは読めない)
# 決済APIは瞬断が多い。恒久障害と切り分けるため最大3回だけ再試行する。
MAX_PAYMENT_RETRIES = 3
while retries < MAX_PAYMENT_RETRIES:
    ...
```

残す価値があるコメントの例:

- 意図・目的 (この関数は何のために存在するか)
- 非自明な判断の理由 (なぜこのアルゴリズム / この定数 / この順序か)
- 仕様・外部制約・既知の落とし穴 (「APIが○○を返す前提」「先に△△しないと壊れる」)
- 公開 API のドキュメント (godoc / docstring / JSDoc)

---

## 原則3: ガード節で早期リターン / continue する

エラーケース・前提を満たさないケースは、関数の**入口で早期リターン**して閉じる。
ループ内なら `continue` で早期に打ち切る。異常系を先に処理しきると、以降は
「正常系だけを考えればよい」状態になり、読み手の負荷が下がる。

```go
// Bad: 正常系が if の内側に潜り、ネストが深くなる
func process(order *Order) error {
    if order != nil {
        if order.Paid {
            if len(order.Items) > 0 {
                return ship(order)
            } else {
                return errors.New("no items")
            }
        } else {
            return errors.New("not paid")
        }
    } else {
        return errors.New("nil order")
    }
}
```

```go
// Good: 異常系をガード節で先に閉じる
func process(order *Order) error {
    if order == nil {
        return errors.New("nil order")
    }
    if !order.Paid {
        return errors.New("not paid")
    }
    if len(order.Items) == 0 {
        return errors.New("no items")
    }
    return ship(order)
}
```

ループでも同じ:

```python
# Good: 対象外を continue で早期に弾き、本処理はネストの外
for user in users:
    if user.is_disabled:
        continue
    if not user.email:
        continue
    send_newsletter(user)
```

---

## 原則4: 正常系は浅いインデントに置く

原則3の帰結。`if status == "OK"` の **then 側で本処理をしない**。
代わりに `if status != "OK"` で早期リターンし、本当に行いたい処理を
**関数スコープの浅い位置**に集約する。読みたいコードの意図が一番浅い所に並ぶ。

```go
// Bad: 本命の処理が then 側の奥にある
if status == "OK" {
    result := doTheRealWork()
    save(result)
    notify(result)
}
return
```

```go
// Good: 異常系で抜け、本命は関数の地の文に並ぶ
if status != "OK" {
    return
}
result := doTheRealWork()
save(result)
notify(result)
```

### 例外: switch 的な if / elif / elif

分岐が「異常系 vs 正常系」ではなく、**同格の複数ケースの振り分け**
(いわゆる switch 相当) の場合は、無理に早期リターンへ潰さない。
むしろ意図が「多方向分岐」であることが伝わる形にする。

```python
# 同格の分岐は無理にガード節化しない。可能なら switch/match で意図を明示
match kind:
    case "circle":
        return circle_area(r)
    case "square":
        return square_area(r)
    case "triangle":
        return triangle_area(r)
    case _:
        raise ValueError(f"unknown kind: {kind}")
```

---

## 原則5: 複雑なワンライナーを避ける

1行に詰め込んだ賢いコードは、書くのは一度・読むのは何度も、という非対称のコスト。
三項演算子の入れ子、長すぎるメソッドチェーン、副作用を織り込んだ内包表記などは、
**適切な変数名を挟んで段階に分ける**。行数は増えても認知負荷は下がる
(cognitive complexity の低減)。

```javascript
// Bad: 何を判定したいのか一読で分からない
const r = u && u.roles && u.roles.find(x => x.a && x.lvl > (u.vip ? 2 : 5)) ? "y" : "n";
```

```javascript
// Good: 中間結果に名前を付け、判断を段階に分ける
const requiredLevel = user?.vip ? 2 : 5;
const hasQualifyingRole = (user?.roles ?? [])
    .some(role => role.active && role.level > requiredLevel);
const result = hasQualifyingRole ? "y" : "n";
```

> 短さ (code golf) は目的ではない。目的は「意図が最短で伝わること」。

---

## 原則6: 意味のある名前をつける (tmp / buf を避ける)

`tmp` `temp` `buf` `data` `val` `flag` `x` のような汎用名は、その変数が
**何であるか**を隠す。名前と構造に意味を持たせる。McConnell の
「1変数=1用途」原則に従い、使い回しもしない。

```go
// Bad: 何が入っているか名前から分からない
tmp := getUser(id)
buf := tmp.Orders
data := 0
for _, x := range buf {
    data += x.Price
}
```

```go
// Good: 役割がそのまま名前になっている
user := getUser(id)
orders := user.Orders
totalPrice := 0
for _, order := range orders {
    totalPrice += order.Price
}
```

- ドメインの語彙で、発音でき検索できる名前にする
- 一時変数でも意味のある名前を付ける (「一時的」は用途であって名前ではない)
- 例外的に許容: ごく狭いスコープの慣習的イテレータ (`i`, `j`)、
  数学的慣習 (`x`, `y` 座標) など、意味が自明な場合のみ

---

## レビュー時チェックリスト

コードを書き終えたら / レビューするときに、この観点で見直す:

- [ ] コードの逐語訳になっている自明なコメントは無いか (原則1)
- [ ] 残したコメントは「why / 目的」を語っているか。「what」なら消せないか (原則2)
- [ ] 前提を満たさないケースを入口のガード節で閉じているか (原則3)
- [ ] 本命の処理が浅いインデントに並んでいるか。深いネストは無いか (原則4)
- [ ] 同格の多方向分岐は switch / match で意図が見えるか (原則4例外)
- [ ] 一読で理解できない詰め込みワンライナーは分解したか (原則5)
- [ ] `tmp` / `buf` / `data` などの汎用名は、役割を表す名前に変えたか (原則6)

## やりすぎ注意 (アンチパターン)

- **ガード節の乱立**: 早期リターンが 5 個も 6 個も並ぶなら、関数が多くの責務を
  抱えているサイン。分割やバリデーションの前段への切り出しを検討する。
- **コメント全消し**: 原則1は「自明なコメント」を消すもの。目的・理由・制約
  (原則2) まで消してはいけない。
- **省略しすぎた名前**: 意味を込めるあまり `theUserWhoJustLoggedInToTheSystem` の
  ように冗長化しない。スコープが狭いほど短くてよい。

## 参考

- Martin Fowler, *Replace Nested Conditional with Guard Clauses* —
  <https://refactoring.com/catalog/replaceNestedConditionalWithGuardClauses.html>
- Refactoring Guru, *Replace Nested Conditional with Guard Clauses* —
  <https://refactoring.guru/replace-nested-conditional-with-guard-clauses>
- Steve McConnell, *Code Complete* (1変数=1用途 / 意味のある命名)
- Clean Code: Meaningful Names —
  <https://codesignal.com/learn/courses/clean-code-basics/lessons/meaningful-names-in-clean-code>
- "Don't name your variables 'temp'" —
  <https://msadowski.github.io/Temp-Variables-Are-Bad/>
- Cognitive Complexity (nested / clever code の認知負荷) —
  <https://www.sonarsource.com/resources/library/cyclomatic-complexity/>
