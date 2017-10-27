import 'dart:async';
import 'dart:html' as html;
import 'package:stagexl/stagexl.dart';
import 'package:stagexl_spine/stagexl_spine.dart';

Future<Null> main() async {
  StageOptions options = new StageOptions()
    ..backgroundColor = Color.White
    ..renderEngine = RenderEngine.Canvas2D;

  var canvas = html.querySelector('#stage');
  var stage = new Stage(canvas, width: 1280, height: 800, options: options);

  var renderLoop = new RenderLoop();
  renderLoop.addStage(stage);

  var resourceManager = new ResourceManager();
  var libgdxx = TextureAtlasFormat.LIBGDX;
  resourceManager.addTextFile("dragon", "export/dragon.json");
  resourceManager.addTextureAtlas("dragon", "export/dragon.atlas", libgdxx);

  await resourceManager.load();

  var spineJson = resourceManager.getTextFile("dragon");
  var textureAtlas = resourceManager.getTextureAtlas("dragon");
  var attachmentLoader = new TextureAtlasAttachmentLoader(textureAtlas);
  var skeletonLoader = new SkeletonLoader(attachmentLoader);
  var skeletonData = skeletonLoader.readSkeletonData(spineJson);

  SkeletonAnimation animation = new SkeletonAnimation(skeletonData)
    ..y = 900
    ..x = 300;
  animation.skeleton.skinName = 'reta';
  stage.addChild(animation);

  animation.state.setAnimationByName(0, 'dragon_neutral', true);
  renderLoop.juggler.add(animation);
}
