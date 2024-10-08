SystemArguments = T.type_alias do
  T::Hash[
    # key
    T.any(Symbol, String),

    # value
    T.any(
      Symbol,
      String,
      Numeric,

      # aria: { ... } and data: { ... }
      T::Hash[
        # key (:aria, "aria", :data, or "data")
        T.any(Symbol, String),

        # value (possibly a nested hash)
        T.any(Symbol, String, T::Hash[
          # key inside aria or data hash
          T.any(Symbol, String),

          # value
          T.any(Symbol, String, Numeric)
        ])
      ]
    )
  ]
end
