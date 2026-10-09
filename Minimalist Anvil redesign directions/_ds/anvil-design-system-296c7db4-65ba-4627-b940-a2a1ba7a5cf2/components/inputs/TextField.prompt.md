The single input primitive in Anvil: an outlined field with a 4px radius, used for the home search bar and every tool parameter.

```jsx
<TextField hint="Search tools" prefixIcon="search" />
<TextField label="Pages per file" type="number" defaultValue={5} />
```

Focus thickens the outline to 2px in primary and floats the label; `error` recolours both to error. Param labels carry their unit inline — "Width (px)", "Start (seconds)" — matching `ToolParam.label` in the Dart source.
