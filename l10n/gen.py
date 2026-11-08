import json,subprocess,os,plistlib
langs=['en','ja','ko','fr','de','es','pt-BR','it','ru']
rows=[]
for f in ['l10n/tr1.tsv','l10n/tr2.tsv','l10n/tr3.tsv']:
    rows+=[l.split('|') for l in open(f).read().split('\n') if l]
tr={l:{} for l in langs+['zh-Hans','zh-Hant']}
for r in rows:
    k=r[0]; tr['zh-Hans'][k]=k
    for i,l in enumerate(langs): tr[l][k]=r[i+1]
keys=[r[0] for r in rows]
hant=subprocess.run(['swift','l10n/hant.swift'],input='\n'.join(keys)+'\n',capture_output=True,text=True).stdout.split('\n')
for k,v in zip(keys,hant): tr['zh-Hant'][k]=v
help={
'zh-Hans':"打开 ⌘↓ / ↩    上层文件夹 ⌘↑ / ⌫    后退 ⌘[    前进 ⌘]\\n新建文件夹 ⇧⌘N    新建文件 ⌥⌘N    重命名 ⌘R    显示简介 ⌘I\\n移到废纸篓 ⌘⌫    复制到 ⌥⌘C    移动到 ⌥⌘V    拷贝/粘贴文件 ⌘C / ⌘V\\n添加到压缩包 ⇧⌘A    解压 ⇧⌘E    测试 ⇧⌘T\\n双栏 ⌥⌘S    切换栏 Tab    显示隐藏文件 ⇧⌘.    刷新 ⇧⌘R\\n前往文件夹 ⇧⌘G    收藏位置 ⌃1–9    设置 ⌘,\\n\\n兼容 Windows 按键：F2 重命名  F5 复制  F6 移动  F7 新建文件夹  F9 双栏  ⌥F12 文件夹历史  ⌥⇧1–9 设为收藏\\n（MacBook 上 F 键需按住 fn）",
'en':"Open ⌘↓ / ↩    Enclosing Folder ⌘↑ / ⌫    Back ⌘[    Forward ⌘]\\nNew Folder ⇧⌘N    New File ⌥⌘N    Rename ⌘R    Get Info ⌘I\\nMove to Trash ⌘⌫    Copy To ⌥⌘C    Move To ⌥⌘V    Copy/Paste files ⌘C / ⌘V\\nAdd to Archive ⇧⌘A    Extract ⇧⌘E    Test ⇧⌘T\\nTwo Panes ⌥⌘S    Switch pane Tab    Show Hidden Files ⇧⌘.    Refresh ⇧⌘R\\nGo to Folder ⇧⌘G    Favorites ⌃1–9    Settings ⌘,\\n\\nWindows-style keys: F2 Rename  F5 Copy  F6 Move  F7 New Folder  F9 Two Panes  ⌥F12 Folder History  ⌥⇧1–9 Set Favorite\\n(On a MacBook, hold fn for F keys)",
'ja':"開く ⌘↓ / ↩    上の階層 ⌘↑ / ⌫    戻る ⌘[    進む ⌘]\\n新規フォルダ ⇧⌘N    新規ファイル ⌥⌘N    名前を変更 ⌘R    情報を見る ⌘I\\nゴミ箱に入れる ⌘⌫    コピー先 ⌥⌘C    移動先 ⌥⌘V    ファイルのコピー／ペースト ⌘C / ⌘V\\nアーカイブに追加 ⇧⌘A    展開 ⇧⌘E    テスト ⇧⌘T\\n2 パネル ⌥⌘S    パネル切替 Tab    隠しファイル ⇧⌘.    更新 ⇧⌘R\\nフォルダへ移動 ⇧⌘G    お気に入り ⌃1–9    設定 ⌘,\\n\\nWindows 互換キー: F2 名前変更  F5 コピー  F6 移動  F7 新規フォルダ  F9 2 パネル  ⌥F12 フォルダ履歴  ⌥⇧1–9 お気に入りに設定\\n（MacBook では fn を押しながら F キー）",
'ko':"열기 ⌘↓ / ↩    상위 폴더 ⌘↑ / ⌫    뒤로 ⌘[    앞으로 ⌘]\\n새로운 폴더 ⇧⌘N    새로운 파일 ⌥⌘N    이름 변경 ⌘R    정보 가져오기 ⌘I\\n휴지통으로 이동 ⌘⌫    다음으로 복사 ⌥⌘C    다음으로 이동 ⌥⌘V    파일 복사/붙여넣기 ⌘C / ⌘V\\n압축 파일에 추가 ⇧⌘A    압축 풀기 ⇧⌘E    테스트 ⇧⌘T\\n두 패널 ⌥⌘S    패널 전환 Tab    숨김 파일 ⇧⌘.    새로 고침 ⇧⌘R\\n폴더로 이동 ⇧⌘G    즐겨찾기 ⌃1–9    설정 ⌘,\\n\\nWindows 호환 키: F2 이름 변경  F5 복사  F6 이동  F7 새 폴더  F9 두 패널  ⌥F12 폴더 기록  ⌥⇧1–9 즐겨찾기 지정\\n(MacBook에서는 fn을 누른 채 F 키)",
'fr':"Ouvrir ⌘↓ / ↩    Dossier parent ⌘↑ / ⌫    Précédent ⌘[    Suivant ⌘]\\nNouveau dossier ⇧⌘N    Nouveau fichier ⌥⌘N    Renommer ⌘R    Lire les informations ⌘I\\nPlacer dans la Corbeille ⌘⌫    Copier vers ⌥⌘C    Déplacer vers ⌥⌘V    Copier/coller des fichiers ⌘C / ⌘V\\nAjouter à l'archive ⇧⌘A    Extraire ⇧⌘E    Tester ⇧⌘T\\nDeux panneaux ⌥⌘S    Changer de panneau Tab    Fichiers masqués ⇧⌘.    Actualiser ⇧⌘R\\nAller au dossier ⇧⌘G    Favoris ⌃1–9    Réglages ⌘,\\n\\nTouches façon Windows : F2 Renommer  F5 Copier  F6 Déplacer  F7 Nouveau dossier  F9 Deux panneaux  ⌥F12 Historique  ⌥⇧1–9 Définir un favori\\n(Sur MacBook, maintenez fn pour les touches F)",
'de':"Öffnen ⌘↓ / ↩    Übergeordneter Ordner ⌘↑ / ⌫    Zurück ⌘[    Vorwärts ⌘]\\nNeuer Ordner ⇧⌘N    Neue Datei ⌥⌘N    Umbenennen ⌘R    Informationen ⌘I\\nIn den Papierkorb ⌘⌫    Kopieren nach ⌥⌘C    Bewegen nach ⌥⌘V    Dateien kopieren/einsetzen ⌘C / ⌘V\\nZum Archiv hinzufügen ⇧⌘A    Entpacken ⇧⌘E    Testen ⇧⌘T\\nZwei Bereiche ⌥⌘S    Bereich wechseln Tab    Unsichtbare Dateien ⇧⌘.    Aktualisieren ⇧⌘R\\nGehe zum Ordner ⇧⌘G    Favoriten ⌃1–9    Einstellungen ⌘,\\n\\nWindows-Tasten: F2 Umbenennen  F5 Kopieren  F6 Bewegen  F7 Neuer Ordner  F9 Zwei Bereiche  ⌥F12 Ordnerverlauf  ⌥⇧1–9 Favorit setzen\\n(Auf dem MacBook für F-Tasten fn gedrückt halten)",
'es':"Abrir ⌘↓ / ↩    Carpeta contenedora ⌘↑ / ⌫    Atrás ⌘[    Adelante ⌘]\\nNueva carpeta ⇧⌘N    Nuevo archivo ⌥⌘N    Renombrar ⌘R    Obtener información ⌘I\\nTrasladar a la Papelera ⌘⌫    Copiar a ⌥⌘C    Mover a ⌥⌘V    Copiar/pegar archivos ⌘C / ⌘V\\nAñadir al archivo ⇧⌘A    Extraer ⇧⌘E    Probar ⇧⌘T\\nDos paneles ⌥⌘S    Cambiar de panel Tab    Archivos ocultos ⇧⌘.    Actualizar ⇧⌘R\\nIr a la carpeta ⇧⌘G    Favoritos ⌃1–9    Ajustes ⌘,\\n\\nTeclas estilo Windows: F2 Renombrar  F5 Copiar  F6 Mover  F7 Nueva carpeta  F9 Dos paneles  ⌥F12 Historial  ⌥⇧1–9 Fijar favorito\\n(En un MacBook, mantén pulsada fn para las teclas F)",
'pt-BR':"Abrir ⌘↓ / ↩    Pasta Superior ⌘↑ / ⌫    Voltar ⌘[    Avançar ⌘]\\nNova Pasta ⇧⌘N    Novo Arquivo ⌥⌘N    Renomear ⌘R    Obter Informações ⌘I\\nMover para o Lixo ⌘⌫    Copiar para ⌥⌘C    Mover para ⌥⌘V    Copiar/colar arquivos ⌘C / ⌘V\\nAdicionar ao Arquivo ⇧⌘A    Extrair ⇧⌘E    Testar ⇧⌘T\\nDois Painéis ⌥⌘S    Trocar painel Tab    Arquivos Ocultos ⇧⌘.    Atualizar ⇧⌘R\\nIr para a Pasta ⇧⌘G    Favoritos ⌃1–9    Ajustes ⌘,\\n\\nTeclas estilo Windows: F2 Renomear  F5 Copiar  F6 Mover  F7 Nova Pasta  F9 Dois Painéis  ⌥F12 Histórico  ⌥⇧1–9 Definir favorito\\n(No MacBook, mantenha fn pressionada para as teclas F)",
'it':"Apri ⌘↓ / ↩    Cartella superiore ⌘↑ / ⌫    Indietro ⌘[    Avanti ⌘]\\nNuova cartella ⇧⌘N    Nuovo file ⌥⌘N    Rinomina ⌘R    Ottieni informazioni ⌘I\\nSposta nel Cestino ⌘⌫    Copia in ⌥⌘C    Sposta in ⌥⌘V    Copia/incolla file ⌘C / ⌘V\\nAggiungi all'archivio ⇧⌘A    Estrai ⇧⌘E    Verifica ⇧⌘T\\nDue pannelli ⌥⌘S    Cambia pannello Tab    File nascosti ⇧⌘.    Aggiorna ⇧⌘R\\nVai alla cartella ⇧⌘G    Preferiti ⌃1–9    Impostazioni ⌘,\\n\\nTasti stile Windows: F2 Rinomina  F5 Copia  F6 Sposta  F7 Nuova cartella  F9 Due pannelli  ⌥F12 Cronologia  ⌥⇧1–9 Imposta preferito\\n(Su MacBook tieni premuto fn per i tasti F)",
'ru':"Открыть ⌘↓ / ↩    Папка выше ⌘↑ / ⌫    Назад ⌘[    Вперед ⌘]\\nНовая папка ⇧⌘N    Новый файл ⌥⌘N    Переименовать ⌘R    Свойства ⌘I\\nВ Корзину ⌘⌫    Копировать в ⌥⌘C    Переместить в ⌥⌘V    Копировать/вставить файлы ⌘C / ⌘V\\nДобавить в архив ⇧⌘A    Извлечь ⇧⌘E    Проверить ⇧⌘T\\nДве панели ⌥⌘S    Сменить панель Tab    Скрытые файлы ⇧⌘.    Обновить ⇧⌘R\\nПереход к папке ⇧⌘G    Избранное ⌃1–9    Настройки ⌘,\\n\\nКлавиши в стиле Windows: F2 Переименовать  F5 Копировать  F6 Переместить  F7 Новая папка  F9 Две панели  ⌥F12 История  ⌥⇧1–9 Задать избранное\\n(На MacBook удерживайте fn для клавиш F)",
}
hh=subprocess.run(['swift','l10n/hant.swift'],input=help['zh-Hans']+'\n',capture_output=True,text=True).stdout.strip()
help['zh-Hant']=hh
svc_keys=['iDipper：添加到压缩包…','iDipper：压缩为 .7z','iDipper：压缩为 .zip','iDipper：解压到当前位置','iDipper：解压到同名文件夹','iDipper：CRC SHA 校验']
out='Resources'; os.system('rm -rf Resources/*.lproj')
esc=lambda s:s.replace('"','\\"')
for l,d in tr.items():
    p=f'{out}/{l}.lproj'; os.makedirs(p)
    with open(p+'/Localizable.strings','w') as f:
        for k,v in d.items(): f.write(f'"{esc(k)}" = "{esc(v)}";\n')
        f.write(f'"SHORTCUT_HELP" = "{esc(help[l])}";\n')
    name='iDipper'
    open(p+'/InfoPlist.strings','w').write(f'"CFBundleName" = "{name}";\n"CFBundleDisplayName" = "{name}";\n')
    with open(p+'/ServicesMenu.strings','w') as f:
        for k in svc_keys: f.write(f'"{esc(tr["en"][k])}" = "{esc(d[k])}";\n')
d=plistlib.load(open('Info.plist','rb'))
for sv,k in zip(d['NSServices'],svc_keys): sv['NSMenuItem']['default']=tr['en'][k]
d['CFBundleDevelopmentRegion']='en'
d['CFBundleLocalizations']=list(tr.keys())
plistlib.dump(d,open('Info.plist','wb'))
print('ok', {l:len(v) for l,v in tr.items()})
