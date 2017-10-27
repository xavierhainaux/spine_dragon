import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:html';
import 'package:stagexl/stagexl.dart';
import 'package:stagexl_spine/stagexl_spine.dart';

main() {
  new SpineTester();
}

final RenderLoop renderLoop = new RenderLoop();
Juggler get sharedJuggler => renderLoop.juggler;

class SpineTester {
  int sceneWidth = 1280;
  int sceneHeight = 720;
  Stage stage;
  Interface interface;

  Map<String, BitmapData> loadeBitmapDatas;
  Map<String, AssetState> assetStateList;
  _SpineFile spineFile;
  SkeletonAnimation skeletonAnimation;

  bool assetsDirty = false, jsonDirty = false;

  SpineTester() {
    sceneWidth = html.document.documentElement.clientWidth;
    sceneHeight = html.document.documentElement.clientHeight;
    loadeBitmapDatas = new Map<String, BitmapData>();
    assetStateList = new Map<String, AssetState>();

    html.Element body = html.querySelector('body');
    html.CanvasElement canvas = new html.Element.canvas()
      ..setAttribute('width', '$sceneWidth')
      ..setAttribute('height', '$sceneHeight')
      ..setAttribute('style',
          'left : 50%; top:50%; margin-left :-${sceneWidth*.5}px; margin-top:-${sceneHeight*.5}px; position: absolute;');
    body
      ..setAttribute('style', 'background-color : hsl(0, 0%, 75%);')
      ..append(canvas);
    interface = new Interface(body, this);

    StageOptions options = new StageOptions()
      ..renderEngine = RenderEngine.Canvas2D;

    stage = new Stage(canvas, options: options);
    stage.backgroundColor = Color.WhiteSmoke;
    renderLoop.addStage(stage);

    html.window.document
      ..onDragEnter.listen(_cancel)
      ..onDragEnd.listen(_cancel)
      ..onDragOver.listen(_cancel)
      ..onDragLeave.listen(_cancel)
      ..onDrop.listen(drop);
  }

  void _cancel(html.MouseEvent e) => e.preventDefault();

  drop(html.MouseEvent e) async {
    e.preventDefault();

    List<html.File> files = [];

    List<html.DataTransferItem> items = [];
    for (int i = 0; i < e.dataTransfer.items.length; i++) {
      items.add(e.dataTransfer.items[i]);
    }

    await _getFiles(items.map((i) => i.getAsEntry()).toList(), files);

    for (html.File file in files) {
      await _fileHandling(file);
    }
    updateContentList();
  }

  Future _getFiles(List<html.Entry> entries, List<html.File> target) async {
    for (html.FileEntry fileEntry
        in entries.where((e) => e is html.FileEntry)) {
      target.add(await fileEntry.file());
    }

    for (html.DirectoryEntry dirEntry
        in entries.where((e) => e is html.DirectoryEntry)) {
      var entries = await dirEntry.createReader().readEntries();
      await _getFiles(entries, target);
    }
  }

  void clear() {
    spineFile = null;
    loadeBitmapDatas.clear();
    assetStateList.clear();
    originAttachmentsNames.clear();
    formatedAttachmentsNames.clear();
    interface.clear();

    clearSkeleton();
  }

  void clearSkeleton() {
    if (skeletonAnimation != null) {
      skeletonAnimation.removeFromParent();
      sharedJuggler.remove(skeletonAnimation);
      skeletonAnimation = null;
    }
  }

  Future _fileHandling(html.File file) async {
    String nameComplete = file.name;
    //si le fichier a une extension
    if (nameComplete.contains('.')) {
      List<String> pathName$Extension = nameComplete.split('.');

      if (pathName$Extension != null && pathName$Extension.length > 1) {
        String name = pathName$Extension[0];

        String extension = pathName$Extension[1].toLowerCase();

        html.FileReader reader = new html.FileReader();
        html.Blob slice = file.slice(0, file.size);

        if (extension == 'png' || extension == 'jpg') {
          name = _formatName(name);
          reader.readAsDataUrl(slice);

          await reader.onLoad.first;
          String content = reader.result;
          content =
              content.replaceFirst('data:;', 'data:image/' + extension + ';');

          html.ImageElement img = new html.ImageElement(src: content);
          await img.onLoad.first;
          BitmapData bitmapData = new BitmapData.fromImageElement(img);
          loadeBitmapDatas['$name'] = bitmapData;
          assetsDirty = true;
        } else if (extension == 'json') {
          reader.readAsText(slice);
          await reader.onLoad.first;
          String content = reader.result;
          if (_SpineFile.isSpineFile(content)) {
            spineFile = new _SpineFile(file, content);
            jsonDirty = true;
          }
        }
      }
    } else {
      _showAlert('file $nameComplete has no extension');
    }
  }

  void updateContentList() {
    bool spineGenerationAllowed = true;
    bool assetsListNeedUpdate = jsonDirty || assetsDirty;

    if (spineFile == null) {
      spineGenerationAllowed = false;
    }

    if (jsonDirty) {
      jsonDirty = false;
      interface.updateJsonName(spineFile.name);
      clearSkeleton();

      spineFile.attachmentNames.forEach((name) {
        AssetState assetState = AssetState.expected;
        //check if asset is already loaded
        //then its completed otherwise its missing
        if (loadeBitmapDatas.keys.contains(name) == true) {
          assetState = missingAssetCheck(name);
        } else {
          ///add an empty bitmap data so an incomplete spine animation can be created
          loadeBitmapDatas['$name'] =
              new BitmapData(1, 1, Color.Transparent);
          assetState = AssetState.expected;
        }
        assetStateList[name] = assetState;
      });

      List<String> names = assetStateList.keys.toList();
      for (String name in names) {
        //check if any unloaded asset is not expected anymore
        if (spineFile.attachmentNames.contains(name) == false) {
          if (assetStateList[name] == AssetState.expected) {
            assetStateList.remove(name);
          } else if (assetStateList[name] == AssetState.completed) {
            assetStateList[name] = AssetState.present;
          }
        }
      }
    }

    if (assetsDirty) {
      assetsDirty = false;

      if (spineFile != null) {
        spineFile.attachmentNames.forEach((name) {
          AssetState assetState = AssetState.expected;
          //check if any loaded assets is part of the json
          if (loadeBitmapDatas.keys.contains(name) == true) {
            assetState = missingAssetCheck(name);
          }
          assetStateList[name] = assetState;
        });
      }

      loadeBitmapDatas.keys.forEach((name) {
        //check if any asset is not present yet
        if (assetStateList.containsKey(name) == false) {
          assetStateList[name] = AssetState.present;
        }
      });
    }

    if (assetsListNeedUpdate) {
      interface.updateAssetsList(assetStateList);
    }

    if (assetsListNeedUpdate && spineGenerationAllowed) {
      _handleSpineJsonFile();
    }
  }

  AssetState missingAssetCheck(String name) {
    if (loadeBitmapDatas[name].width == 1 &&
        loadeBitmapDatas[name].height == 1) {
      return AssetState.expected;
    } else {
      return AssetState.completed;
    }
  }

  clearUnusedAssets() {
    if (spineFile != null) {
      bool isAnyCleared = false;
      List<String> names = loadeBitmapDatas.keys.toList();
      for (String name in names) {
        if (spineFile.attachmentNames.contains(name) == false) {
          assetStateList.remove(name);
          loadeBitmapDatas.remove(name);
          isAnyCleared = true;
        }
      }
      if (isAnyCleared) {
        interface.updateAssetsList(assetStateList);
      }
    }
  }

  void _showAlert(String message) {
    if (!html.window.navigator.dartEnabled) {
      html.window.alert(message);
    } else {
      throw new ArgumentError(message);
    }
  }

  void _handleSpineJsonFile() {
    SkeletonData skeletonData = new SkeletonData();

    if (skeletonAnimation != null) {
      skeletonAnimation.removeFromParent();
    }
    Map<String, BitmapData> data = new Map<String, BitmapData>();

    for (int i = 0; i < originAttachmentsNames.length; ++i) {
      data[originAttachmentsNames[i]] =
          loadeBitmapDatas[formatedAttachmentsNames[i]];
    }

    skeletonData = _generateSkeletonData(spineFile.json, data);
    AnimationStateData animStateData = new AnimationStateData(skeletonData);
    skeletonAnimation = new SkeletonAnimation(skeletonData, animStateData)
      ..x = sceneWidth * .5
      ..y = sceneHeight * .5;

    interface
      ..createAnimationsButtons(spineFile.animationsNames.toList())
      ..updateFieldOffset(skeletonAnimation.x, skeletonAnimation.y);

    skeletonAnimation.state
        .setAnimationByName(0, spineFile.animationsNames.elementAt(0), true);

    if (spineFile.skinNames.length > 0) {
      skeletonAnimation.skeleton.skinName = spineFile.skinNames.elementAt(0);
      interface.createSkinButtons(spineFile.skinNames.toList());
    }

    sharedJuggler.add(skeletonAnimation);
    stage.addChild(skeletonAnimation);
  }

  void playAnimation(String name) {
    if (spineFile != null) {
      skeletonAnimation.state.setAnimationByName(0, name, true);
    }
  }

  void updateSkin(String name) {
    if (spineFile != null && spineFile.skinNames.contains(name)) {
      skeletonAnimation.skeleton.skinName = name;
    }
  }

  SkeletonData _generateSkeletonData(
      Map<String, dynamic> data, Map<String, BitmapData> attachments) {
    SkeletonLoader loader =
        new SkeletonLoader(new MappedAttachmentLoader(attachments));
    SkeletonData skeletonData = loader.readSkeletonData(data);

    return skeletonData;
  }

  void updateSkeletonOffset(double x, double y) {
    if (skeletonAnimation != null) {
      skeletonAnimation
        ..x = x
        ..y = y;
    }
  }

  void updateSkeletonMix(num mix) {
    skeletonAnimation.state.data.defaultMix = mix;
  }

  void switchBackground({bool toWhite}) {
    if (toWhite) {
      stage.backgroundColor = Color.WhiteSmoke;
    } else {
      stage.backgroundColor = Color.DimGray;
    }
  }
}

String _formatName(String name) {
  return name.replaceAll(' ', '').replaceAll('_', '').toLowerCase();
}

List<String> originAttachmentsNames = [];
List<String> formatedAttachmentsNames = [];

class _SpineFile {
  final Map json;
  final String name;
  final Set<String> attachmentNames = new Set();
  final Set<String> animationsNames = new Set();
  final Set<String> eventsNames = new Set();
  final Set<String> skinNames = new Set();

  _SpineFile(html.File file, String fileContent)
      : json = JSON.decode(fileContent),
        name = file.name {
    // unwanted Path attrachment names
    Set<String> pathAttachementNames = new Set();

    // Skins explore to find assets
    Map skins = json['skins'];
    if (skins != null) {
      for (String skinName in skins.keys) {
        Map skinMap = skins[skinName];
        for (String slotName in skinMap.keys) {
          Map slotEntry = skinMap[slotName];

          for (String attachmentName in slotEntry.keys) {
            if (slotEntry[attachmentName]['type'] == 'path') {
              originAttachmentsNames.add(attachmentName);
              String formatedName = _formatName(attachmentName);
              formatedAttachmentsNames.add(formatedName);

              pathAttachementNames.add(attachmentName);
            } else if (slotEntry[attachmentName]["name"] != null) {
              String originName =
                  slotEntry[attachmentName]["name"].split('/').last;
              originAttachmentsNames.add(originName);
              String formatedName = _formatName(originName);
              formatedAttachmentsNames.add(formatedName);

              attachmentNames.add(formatedName);
            } else if (slotEntry[attachmentName]['path'] != null) {
              String originName =
                  slotEntry[attachmentName]['path'].split('/').last;
              originAttachmentsNames.add(originName);
              String formatedName = _formatName(originName);
              formatedAttachmentsNames.add(formatedName);

              attachmentNames.add(formatedName);
            } else {
              String originName = attachmentName.split('/').last;
              originAttachmentsNames.add(originName);
              String formatedName = _formatName(originName);
              formatedAttachmentsNames.add(formatedName);

              attachmentNames.add(formatedName);
            }
          }
        }

        if (skinName != 'default') {
          skinNames.add(skinName);
        }
      }
    }

    //Animations
    Map<String, dynamic> animations = json['animations'];
    if (animations != null) {
      for (String animationName in animations.keys) {
        if (!(animations[animationName]["slots"] is Map)) continue;

        for (String subKey in animations[animationName]["slots"].keys) {
          if (animations[animationName]["slots"][subKey]["attachment"] !=
                  null &&
              animations[animationName]["slots"][subKey]["attachment"]
                  is List<Map>) {
            for (Map slotAttachment in animations[animationName]["slots"]
                [subKey]["attachment"]) {
              if (slotAttachment["name"] != null &&
                  slotAttachment["name"] is String &&
                  !pathAttachementNames.contains(slotAttachment["name"])) {
                String originName = slotAttachment["name"].split('/').last;
                originAttachmentsNames.add(originName);
                String formatedName = _formatName(originName);
                formatedAttachmentsNames.add(formatedName);
                attachmentNames.add(formatedName);
              }
            }
          }
        }
      }

      animationsNames.addAll(animations.keys);
    }

    Map<String, dynamic> events = json['events'];
    if (events != null) {
      eventsNames.addAll(events.keys);
    }
  }

  static bool isSpineFile(String content) {
    return content.contains('"skeleton":') && content.contains('"spine":');
  }
}

abstract class AbstractAttachmentLoader implements AttachmentLoader {
  @override
  RegionAttachment newRegionAttachment(Skin skin, String name, String path) {
    return new RegionAttachment(name, path, getBitmapData(path));
  }

  @override
  MeshAttachment newMeshAttachment(Skin skin, String name, String path) {
    return new MeshAttachment(name, path, getBitmapData(path));
  }

  @override
  BoundingBoxAttachment newBoundingBoxAttachment(Skin skin, String name) {
    return new BoundingBoxAttachment(name);
  }

  @override
  PathAttachment newPathAttachment(Skin skin, String name) {
    return new PathAttachment(name);
  }

  BitmapData getBitmapData(String name);

  @override
  ClippingAttachment newClippingAttachment(Skin skin, String name) {
    return new ClippingAttachment(name);
  }

  @override
  PointAttachment newPointAttachment(Skin skin, String name) {
    return new PointAttachment(name);
  }
}

class MappedAttachmentLoader extends AbstractAttachmentLoader {
  final Map<String, BitmapData> attachments;

  MappedAttachmentLoader(this.attachments);

  getBitmapData(String attachmentName) {
    String name = attachmentName.split("/").last;
    try {
      return attachments[name];
    } catch (e) {
      throw "Cannot find attachment $name";
    }
  }
}

enum AssetState { expected, present, completed }

class Interface {
  BodyElement body;
  ButtonElement clearButton, clearUnusedButton;
  ParagraphElement jsonName, assetList;
  DivElement assetsBar, animationsBar;
  NumberInputElement inputX, inputY, inputMix;
  SpineTester spineTester;

  Interface(this.body, this.spineTester) {
    clearButton = new ButtonElement()
      ..text = 'clear All'
      ..onClick.listen((_) {
        spineTester.clear();
      });
    clearUnusedButton = new ButtonElement()
      ..text = 'clear unused assets'
      ..onClick.listen((_) {
        spineTester.clearUnusedAssets();
      });
    jsonName = new ParagraphElement()
      ..setAttribute('style', 'text-align : right;');
    assetList = new ParagraphElement()
      ..setAttribute('style', 'text-align : right;');

    assetsBar = new DivElement()
      ..attributes = {
        'style': 'width : 250px;'
            'height: 100%;'
            'float : right;'
            'position : fixed;'
            'right : 0%;'
            'top : 0px;'
            'background-color : hsla(0, 0%, 90%, 0.5);'
            'overflow: scroll;'
      }
      ..append(clearButton)
      ..append(clearUnusedButton)
      ..append(jsonName)
      ..append(assetList);

    animationsBar = new DivElement()
      ..attributes = {
        'style': 'width : 250px;'
            'height: 100%;'
            'float : left;'
            'position : fixed;'
            'left : 0px;'
            'top : 0px;'
            'background-color : hsla(0, 0%, 90%, 0.5);'
            'overflow: scroll;'
      };

    ParagraphElement instructions = new ParagraphElement()
      ..innerHtml =
          '<b>Instructions :</b> Drag-doppez les assets et .json de spine dans la fenêtre '
          'pour les charger. '
          'Les assets chargés sont inscrits en <span id="blue">bleu</span>. '
          '<br>Lorsqu\'un fichier .json est chargé les assets manquant qu\'il '
          'requiert seront inscrits en <span id="red">rouge</span> et ceux qui sont '
          'déjà chargés en <span id="green">verts</span>.<br><b>Les noms des assets '
          'et des attachments doivent être similaires</b>.'
          '<br><b>Tips :</b> Attention aux espaces résiduels dans les noms de fichiers '
          'et d\'attachments et à la casse. Un nom ne peut commencer par chiffre.'
      ..setAttribute(
          'style',
          'width : 63%;'
              'height : 50px;'
              'position : absolute;'
              'left : 50%;'
              'margin-left : -30%;'
              'bottom : 5%;');

    StyleElement style = new StyleElement()
      ..innerHtml = '#blue {color : blue;}'
          '#green {color : green;}'
          '#red {color : red;}';
    querySelector('head').append(style);

    inputX = new NumberInputElement()..setAttribute('style', 'width : 50px;');
    inputY = new NumberInputElement()..setAttribute('style', 'width : 50px;');
    Function inputBehavior = () {
      double x =
      inputX.valueAsNumber.isNaN ? 0.0 : inputX.valueAsNumber.toDouble();
      double y =
      inputY.valueAsNumber.isNaN ? 0.0 : inputY.valueAsNumber.toDouble();
      inputX.valueAsNumber = x;
      inputY.valueAsNumber = y;
      spineTester.updateSkeletonOffset(x, y);
    };
    inputX.onChange.listen((_) {
      inputBehavior();
    });
    inputY.onChange.listen((_) {
      inputBehavior();
    });

    ButtonInputElement resetOffset = new ButtonInputElement()
      ..value = 'reset'
      ..setAttribute('style', 'margin-left : 12px;')
      ..onClick.listen((_) {
        _.preventDefault();
        updateFieldOffset(0.0, 0.0);
        spineTester.updateSkeletonOffset(0.0, 0.0);
      });

    inputMix = new NumberInputElement()..setAttribute('style', 'width : 50px;');
    inputMix.onChange.listen((_) {
      spineTester.updateSkeletonMix(inputMix.valueAsNumber);
    });

    ButtonInputElement bgSwitch = new ButtonInputElement()..value = 'Black';
    bgSwitch
      ..onClick.listen((_) {
        if (bgSwitch.value == 'Black') {
          bgSwitch.value = 'White';
          spineTester.switchBackground(toWhite: false);
        } else {
          bgSwitch.value = 'Black';
          spineTester.switchBackground(toWhite: true);
        }
      });

    FieldSetElement offsetField = new FieldSetElement()
      ..append(new LegendElement()..text = 'Offset')
      ..appendText('x:')
      ..append(inputX)
      ..append(new BRElement())
      ..appendText('y:')
      ..append(inputY)
      ..append(new BRElement())
      ..append(resetOffset);
    FieldSetElement mixField = new FieldSetElement()
      ..append(new LegendElement()..text = 'Mix/Blend')
      ..append(inputMix);
    FieldSetElement bgField = new FieldSetElement()
      ..append(new LegendElement()..text = 'Background')
      ..append(bgSwitch);
    FormElement offsetForm = new FormElement()
      ..append(offsetField)
      ..append(mixField)
      ..append(bgField)
      ..setAttribute(
          'style',
          'left :260px;'
              'bottom :5%;'
              'position : absolute;');

    body
      ..append(assetsBar)
      ..append(animationsBar)
      ..append(instructions)
      ..append(offsetForm);

    clear();
  }

  void updateFieldOffset(num x, num y) {
    inputX.value = '$x';
    inputY.value = '$y';
  }

  void updateAssetsList(Map<String, AssetState> assets) {
    assetList.innerHtml = 'Current Loaded Assets :<br>';
    assets.forEach((name, state) {
      String color = 'grey';
      switch (state) {
        case AssetState.expected:
          color = 'red';
          break;
        case AssetState.present:
          color = 'blue';
          break;
        case AssetState.completed:
          color = 'green';
          break;
      }
      SpanElement spanElement = new SpanElement()
        ..text = '$name'
        ..setAttribute('style', 'color : $color;');
      assetList..append(spanElement)..append(new BRElement());
    });
  }

  void updateJsonName(String newName) {
    jsonName.innerHtml = 'Current JSON file :<br>$newName';
    clearAnimationsButtons();
    animationsBar
        .append(new ParagraphElement()..text = 'No animations available');
  }

  void clear() {
    assetList.text = 'no assets loaded';
    jsonName.text = 'no .json loaded';

    clearAnimationsButtons();
    animationsBar
        .append(new ParagraphElement()..text = 'No animations available');
  }

  void createAnimationsButtons(List<String> animationsNames) {
    clearAnimationsButtons();

    animationsBar.append(new ParagraphElement()..text = 'Animations List :');

    for (int i = 0; i < animationsNames.length; ++i) {
      String animationName = animationsNames[i];
      int width = animationName.length * 10;
      ButtonElement button = new ButtonElement()
        ..text = animationName
        ..setAttribute(
            'style',
            'width : ${width}px;'
                'height :25px;left : 50%;'
                'margin-left :-${width*.5}px;'
                'position: relative;'
                'margin-top:5px')
        ..onClick.listen((_) {
          spineTester.playAnimation(animationName);
        });
      animationsBar..append(button)..append(new BRElement());
    }
  }

  void createSkinButtons(List<String> skinsNames) {
    animationsBar
      ..append(new BRElement())
      ..append(new ParagraphElement()..text = 'Skin List :');

    for (int i = 0; i < skinsNames.length; ++i) {
      String skinName = skinsNames[i];
      int width = skinName.length * 10;
      ButtonElement button = new ButtonElement()
        ..text = skinName
        ..setAttribute(
            'style',
            'width : ${width}px;'
                'height :25px;left : 50%;'
                'margin-left :-${width*.5}px;'
                'position: relative;'
                'margin-top:5px')
        ..onClick.listen((_) {
          spineTester.updateSkin(skinName);
        });
      animationsBar..append(button)..append(new BRElement());
    }
  }

  void clearAnimationsButtons() {
    int childsCount = animationsBar.childNodes.length;

    if (childsCount > 0) {
      List<Node> childs = animationsBar.childNodes.toList();
      for (Node child in childs) {
        child.remove();
      }
    }
  }
}