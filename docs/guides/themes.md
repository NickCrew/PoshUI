# Themes

The Unanet theme is active by default. It uses the brand navy, cyan, and lime palette while preserving semantic status colors.

## Switch built-in themes

```powershell
Set-PoshUITheme -Name dark
Set-PoshUITheme -Name light
Set-PoshUITheme -Name unanet
```

The switch affects subsequent rich rendering immediately. Plain and off modes continue to remove control sequences.

## Customize a theme

Start with a built-in theme so every required token is present, change the tokens your application owns, then activate the result:

```powershell
$theme = New-PoshUITheme -Name unanet
$theme.Name = 'release-console'
$theme.Component.Box.Border = "`e[38;2;82;214;255m"
$theme.Component.Table.Header = "`e[1;38;2;173;232;58m"
$theme | Set-PoshUITheme
```

PoshUI copies the supplied theme before activation. Later changes to `$theme` do not mutate the active module state.

## Inspect active tokens

```powershell
$active = (Get-PoshUIConfiguration).Theme
$active.Semantic
$active.Component.Table
```

`Get-PoshUIConfiguration` also returns an independent copy. Treat primitive tokens as terminal mechanics, semantic tokens as meaning, and component tokens as the final styling contract for a renderer.
