# What The Input And Output Mean

This file explains what happens when you type a name into the FPGA inference demo and what the output means.

## Short version

When you type a name like:

```text
emma
```

the system does **not** look up similar names in a database.

Instead, it does this:

1. It treats the name as a sequence of characters.
2. It feeds those characters into a tiny character-level model.
3. The model predicts the next character.
4. Then it feeds that predicted character back in and predicts another one.
5. It repeats this for up to the requested number of steps.

So the output is a **generated continuation**, not a list of matching names.

## Example

If you run:

```powershell
.\run_inference.bat --prompt emma --steps 8 --stream
```

and see:

```text
nnnnqqqq
status=0x0B080435
done=True error=False
tokens=[13, 13, 13, 13, 16, 16, 16, 16]
text=nnnnqqqq
```

this means:

- your input prompt was `emma`
- the model generated 8 more characters
- those generated characters were `n n n n q q q q`

It does **not** mean:

- `emma` is similar to `nnnnqqqq`
- `nnnnqqqq` is a real name
- the model understands names like a human does

It only means:

- after reading `e m m a`, this tiny model predicted the next character as `n`
- then after that state update it predicted another `n`
- then another `n`
- then eventually `q`

## What `tokens=[...]` means

The model works internally with token IDs, not letters.

In this project the vocabulary is:

```text
a b c d e f g h i j k l m n o p q r s t u v w x y z ^
```

where:

- `a = 0`
- `b = 1`
- ...
- `n = 13`
- `q = 16`
- `^ = 26`

So:

```text
tokens=[13, 13, 13, 13, 16, 16, 16, 16]
```

means:

```text
n n n n q q q q
```

## What `text=...` means

The `text=` line is just the token IDs decoded back into letters.

So:

```text
tokens=[13, 13, 13, 13, 16, 16, 16, 16]
text=nnnnqqqq
```

are the same result shown in two different ways.

## What the prompt changes

The prompt changes the model state before generation starts.

Examples:

- prompt `emma` may produce one continuation
- prompt `harry` may produce a different continuation
- prompt `jacob` may produce another continuation

So the prompt matters because it changes the next-character predictions.

But this is still just a tiny character model, so the continuations can look repetitive or weird.

## Is it supposed to generate similar names?

Only loosely.

The model was trained on names, so in principle it is trying to generate character sequences that look like names.

But:

- it is very small
- it has a very small context length
- it only predicts one character at a time
- the current FPGA implementation is not yet an exact reproduction of Karpathy's full microgpt behavior

So it can produce something name-like sometimes, but it can also produce nonsense.

## Does it work for any name?

It works for any prompt that obeys the input rules below.

Allowed prompt rules:

- only lowercase `a-z`
- no spaces
- no punctuation
- no numbers
- no `^`
- length must be shorter than 16 characters

These are valid:

- `emma`
- `harry`
- `jacob`
- `olivia`
- `isabella`

These are not valid:

- `Emma` if you expect uppercase to be preserved
- `mary-jane`
- `o'connor`
- `anna maria`
- `john3`

The script lowercases input, so uppercase letters are converted to lowercase before encoding.

## Does it work only for the names you tried?

No. It is not restricted to only:

- `emma`
- `harry`
- `jacob`

It can accept any prompt that matches the rules above.

But the quality of the result is not guaranteed to be good for every prompt.

## Why some outputs look bad

There are several reasons:

1. The model is tiny.
2. It is character-level, not word-level.
3. The vocabulary is only 27 symbols.
4. The active FPGA kernel is still not a perfect match to Karpathy's full reference behavior.

So the system may be:

- working correctly as an FPGA inference demo
- while still producing low-quality text

Those are different questions.

## What `status=...` means

The `status=` line is a packed hardware status register.

You usually only need these parts:

- `done=True` means generation finished
- `error=False` means no hardware error was reported

If you see:

```text
done=True error=False
```

then the FPGA run completed normally.

## Best way to think about this demo

Think of it as:

> "Given a starting string, the FPGA predicts and appends more characters."

Do **not** think of it as:

> "Search for a matching baby name"

or:

> "Return the closest real name"

It is a tiny generative model, not a lookup engine.

## Bottom line

- The input is a starting sequence of characters.
- The output is a generated continuation of that sequence.
- The output is not guaranteed to be a real or sensible name.
- It works for any valid lowercase prompt shorter than 16 characters.
- It is not limited to just the example names you tried.
