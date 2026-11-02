# disable-windows-services

**[English](#english) | [Português](#português)**

A small, reversible PowerShell script that turns off Windows services and features most desktop users never use: telemetry, error reporting, Superfetch, touch keyboard, fax and **Windows Recall**.

Every change is backed up first, and `-Undo` puts everything back exactly as it was.

---

## English

### What it changes

| Item | What it is | Why turn it off |
|---|---|---|
| `DiagTrack` | Connected User Experiences and Telemetry | Sends usage data to Microsoft |
| `dmwappushservice` | WAP push message routing | Telemetry helper |
| `WerSvc` | Windows Error Reporting | Uploads crash reports |
| `SysMain` | Superfetch | Preloads apps into RAM; little benefit on fast SSD/NVMe |
| `TabletInputService` | Touch keyboard and handwriting | Not needed without a touchscreen |
| `Fax` | Fax service | You know |
| `CDPUserSvc` | Connected Devices Platform | Phone Link, nearby sharing, cross-device sync |
| Recall + Click to Do | Windows 11 AI features | Recall keeps taking screenshots of your activity |

Items that don't exist on your Windows version are skipped.

### Usage

Open PowerShell **as Administrator** in the script folder:

```powershell
.\disable-windows-services.ps1 -AnalyzeOnly  # look first, change nothing
.\disable-windows-services.ps1               # disable + analysis
.\disable-windows-services.ps1 -Undo         # restore the original state
```

If PowerShell blocks the script, allow it for this window only:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

Reboot after running.

### How undo works

On the first run the script saves the original startup type of each service, the Recall policy values and whether the Recall feature was on, to `%ProgramData%\disable-windows-services\backup.json`. Later runs never overwrite that file, so `-Undo` always goes back to the real original state.

### Before you run it

- **Touch screen or pen?** Don't disable `TabletInputService`: remove it from the list at the top of the script.
- **Use Phone Link or Nearby Sharing?** Remove `CDPUserSvc` from the list.
- The script also lists other services worth reviewing (Xbox, Print Spooler, Search...). It only **shows** them, it never changes them.
- No warranty. See [LICENSE](LICENSE).

---

## Português

Script PowerShell pequeno e **reversível** que desliga serviços e recursos do Windows que a maioria das pessoas não usa: telemetria, relatório de erros, Superfetch, teclado de toque, fax e o **Recall** do Windows 11 (que fica tirando print da sua tela pra IA buscar depois).

### Como usar

Abra o PowerShell **como Administrador** na pasta do script:

```powershell
.\disable-windows-services.ps1 -AnalyzeOnly  # só olha, não muda nada
.\disable-windows-services.ps1               # desliga + mostra a análise
.\disable-windows-services.ps1 -Undo         # volta tudo como estava
```

Se o Windows bloquear o script, libere só pra essa janela com `Set-ExecutionPolicy -Scope Process Bypass`. Reinicie o PC depois.

### Como o "desfazer" funciona

Na primeira execução, o script salva como cada item estava em `%ProgramData%\disable-windows-services\backup.json`. As próximas execuções nunca sobrescrevem esse arquivo, então o `-Undo` sempre volta ao estado original de verdade.

### Antes de rodar

- **Usa tela touch ou caneta?** Tire o `TabletInputService` da lista no começo do script.
- **Usa o Vincular ao Celular ou o Compartilhamento por Proximidade?** Tire o `CDPUserSvc`.
- Itens que não existem na sua versão do Windows são pulados.
- Sem garantias. Veja a [licença](LICENSE).

## License

[MIT](LICENSE)
