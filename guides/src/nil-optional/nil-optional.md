# nil and Optional Types

`nil`s have been the most common source of the errors you see when testing and after the deployment of your apps.

```
NoMethodError (undefined method `save!' for nil:NilClass)
```

Steep/RBS provides *optional types* to help you identify the problems while you are coding.

## Preventing `nil` problems

Technically, there is only one way to prevent `nil` problems – test everytime if the value is `nil` before calling methods with the receiver.

```rb
if account
  account.save!
end
```

Using the `if` statement is the most popular way to ensure the value is not `nil`. But you can do it with safe-navigation-operators, case-when (or case-in), and `#try` method.

```rb
account&.save!

case account
when Account
  account.save!
end

account.try {|account| account.save! }
```

It's simple, but not easy to do in your code.

**You may forget testing.** This happens easily. You don't notice that you forget until you deploy the code into production and it crashes after loading an account that is old and satisfies complicated conditions that leads it to be `nil`.

**You may add redundant guards.** This won't get your app crash, but it will make understanding your code more difficult. It adds unnecessary noise that tells your teammates this can be `nil` in some place, and results in another redundant guard.

The `nil` problems can be solved by a tool that tells you:

* If the value can be `nil` or not, and
* You forget testing the value before using the value

RBS has a language construct to do this called optional types and Steep implements analysis to let you know if you forget testing the value.

## Optional types

Optional types in RBS are denoted with a suffix `?` – Type?. It means the value of the type may be `nil`.

```
Integer?            # Integer or nil
Array[Account]?     # An array of Account or nil
```

Note that optional types can be included in other types as:

```
Array[Account?]
```

The value of the type above is always an array, but the element may be `nil`.

In other words, a non optional type in RBS means the value cannot be `nil`.

```
Integer            # Integer, cannot be nil
Array[Account]     # An array, cannot be nil
```

Let's see how Steep reports errors on optional and non-optional types.

```rb
account = Account.find(1)
account.save!
```

Assume the type of `account` is `Account` (non optional type), the code type checks successfully. There is no chance to be `nil` here. The `save!` method call never results in a `NoMethodError`.

```rb
account = Account.find_by(email: "soutaro@squareup.com")
account.save!
```

Steep reports a `NoMethod` error on the `save!` call. Because the value of the `account` may be `nil`, depending on the actual records in the `accounts` table. You cannot call the `save!` method without checking if the `account` is `nil`.

You cannot assign `nil` to a local variable with non-optional types.

```rb
# @type var account: Account

account = nil
account = Account.find_by(email: "soutaro@squareup.com")
```

Because the type of `account` is declared Account, non-optional type, it cannot be `nil`. And Steep detects a type error if you try to assign `nil`. Same for assigning an optional type value at the last line.

# Unwrapping optional types

There are several ways to unwrap optional types. The most common one is using if.

```rb
account = Account.find_by(id: 1)
if account
  account.save!
end
```

The *if* statement tests if `account` is `nil`. Inside the then clause, `account` cannot be `nil`. Then Steep type checks the code.

This works for *else* clause of *unless*.

```rb
account = Account.find_by(id: 1)
unless account
  # Do something
else
  account.save!
end
```

This also type checks successfully.

Steep supports `nil?` predicate too.

```rb
unless (account = Account.find_by(id: 1)).nil?
  account.save!
end
```

This assumes the `Account` class doesn't have a custom `nil?` method, but keeps the built-in `nil?` or equivalent.

The last one is using safe-nevigation-navigator. It checks if the receiver is `nil` and calls the method if it is not. Otherwise just evaluates to `nil`.

```rb
account = Account.find_by(id: 1)
account&.save!
```

This is a shorthand for the case you don't do any error handling case if it is `nil`.

## What should I do for the case of `nil`?

There is no universal answer for this question. You may just stop the execution of the method by returning. You may want to insert a new account to ensure the record exists. Raising an exception with a detailed error message will help troubleshooting.

It depends on what the program is expected to do. Steep just checks if accessing `nil` may happen or not. The developers only know how to handle the `nil` cases.

# Handling unwanted `nil`s

When you start using Steep, you may see many unwanted `nil`s. This typically happens when you want to use Array methods, like `first` or `sample`.

```rb
account = accounts.first
account.save!
```

It returns `nil` if the array is empty. Steep cannot detect if the array is empty or not, and it conservatively assumes the return value of the methods may be `nil`. While you know the `account` array is not empty, Steep infer the `first` method may return `nil`.

This is one of the most frequently seen sources of unwanted `nil`s.

## Raising an error

In this case, you have to add an extra code to let Steep unwrap it.

```rb
account = accounts.first or raise
account.save!
```

My recommendation is to raise an exception, `|| raise` or `or raise`. It raises an exception in the case of `nil`, and Steep unwraps the type of the `account` variable.

Exceptions are better than other control flow operators – `return`/`break`/`next`. It doesn't affect the control flow until it actually happens during execution, and the type checking result other than the unwrapping is changed.

An `#raise` call without argument is my favorite. It's short. It's uncommon in the Ruby code and it can tell the readers that something unexpected is happening.

But of course, you can add some message:

```rb
account = accounts.first or raise("accounts cannot be empty")
account.save!
```

## Type assertions

You can also use a type assertion, that is introduced in Steep 1.3.

```rb
account = accounts.first #: Account
account.save!
```

It tells Steep that the right hand side of the assignment is `Account`. That overwrites the type checking algorithm, and the developer is responsible for making sure the value cannot be `nil`.

Note: Nothing happens during the execution. It just works for Steep and Ruby doesn't do any extra type checking on it. I recommend using the `or raise` idiom for most of the cases.
