<p align="center">
  <img src="assets/logo.svg" alt="Tabler Icons" width="80">
</p>

<h1 align="center">Tabler Icons for Flutter</h1>

<p align="center">
  <a href="https://pub.dev/packages/tabler_icons_plus"><img src="https://img.shields.io/pub/v/tabler_icons_plus?color=blue&label=pub.dev" alt="pub.dev"></a>
  <a href="https://www.npmjs.com/package/@tabler/icons"><img src="https://img.shields.io/badge/@tabler/icons-v3.44.0-066fd1" alt="@tabler/icons version"></a>
  <a href="https://tabler.io/icons"><img src="https://img.shields.io/badge/icons-6%2C203-blue" alt="Icon count"></a>
</p>

<p align="center">
  <strong>6,203 open-source <a href="https://tabler.io/icons">Tabler Icons</a></strong> as typed <code>IconData</code> constants for Flutter.<br>
  Drop-in compatible with the <code>Icon</code> widget and theme system.
</p>

<p align="center">
  <a href="https://tabler.io/icons"><strong>Browse all icons &rarr;</strong></a>
</p>

<div align="center">
  <h3>✨ Always Up-to-Date</h3>
  <p>Every new Tabler Icons release is automatically synced and published to <a href="https://pub.dev/packages/tabler_icons_plus">pub.dev</a> daily. <br>Enjoy a continuously refreshed icon library requiring zero manual maintenance.</p>
</div>

---

## Getting Started

Add the package to your `pubspec.yaml`:

```sh
flutter pub add tabler_icons_plus
```

Then import and use:

```dart
import 'package:tabler_icons_plus/tabler_icons_plus.dart';
```

---

## Usage

```dart
// Simple icon
Icon(TablerIcons.home)

// Sized and colored
Icon(TablerIcons.bell, size: 32, color: Colors.blue)

// Inside a button
IconButton(
  icon: Icon(TablerIcons.settings),
  onPressed: () {},
)

// Themed group
IconTheme(
  data: IconThemeData(size: 24, color: Colors.grey),
  child: Row(
    children: [
      Icon(TablerIcons.heart),
      Icon(TablerIcons.star),
      Icon(TablerIcons.user),
    ],
  ),
)
```

---

## Icon Naming

Tabler's kebab-case names are converted to **camelCase**:

| Tabler Name | Dart Constant |
|:--|:--|
| `arrow-left` | `TablerIcons.arrowLeft` |
| `chevron-down` | `TablerIcons.chevronDown` |
| `brand-github` | `TablerIcons.brandGithub` |
| `circle-check` | `TablerIcons.circleCheck` |
| `switch` | `TablerIcons.switch1` |

> **Note:** `switch` is a Dart reserved keyword and is renamed to `switch1` for consistency with `switch2` and `switch3`.

---

## Platforms

<table>
  <tr>
    <td align="center"><strong>Android</strong></td>
    <td align="center"><strong>iOS</strong></td>
    <td align="center"><strong>Web</strong></td>
    <td align="center"><strong>macOS</strong></td>
    <td align="center"><strong>Linux</strong></td>
    <td align="center"><strong>Windows</strong></td>
  </tr>
  <tr>
    <td align="center">&#10003;</td>
    <td align="center">&#10003;</td>
    <td align="center">&#10003;</td>
    <td align="center">&#10003;</td>
    <td align="center">&#10003;</td>
    <td align="center">&#10003;</td>
  </tr>
</table>

---

## License

MIT License. See [LICENSE](LICENSE) for details.

Icon designs by [Paweł Kuna](https://github.com/tabler/tabler-icons) under the [MIT License](https://github.com/tabler/tabler-icons/blob/main/LICENSE).

<p align="center">
  <sub>Built with &#9829; by <a href="https://deveji.com">Deveji</a></sub>
</p>
