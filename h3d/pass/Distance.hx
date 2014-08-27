package h3d.pass;

class Distance extends Base {

	var texture : h3d.mat.Texture;
	var hasTargetDepth : Bool;
	var clear : Clear;

	public function new(name) {
		super(name);
		priority = 10;
		lightSystem = null;
		hasTargetDepth = h3d.Engine.getCurrent().driver.hasFeature(TargetDepthBuffer);
		if( !hasTargetDepth )
			clear = new Clear();
	}

	override function getOutputs() {
		return ["output.position", "output.distance"];
	}

	override function draw(ctx : h3d.scene.RenderContext, passes) {
		if( texture == null || texture.width != ctx.engine.width || texture.height != ctx.engine.height ) {
			if( texture != null ) texture.dispose();
			texture = new h3d.mat.Texture(ctx.engine.width, ctx.engine.height, [Target, hasTargetDepth ? TargetDepth : TargetUseDefaultDepth, TargetNoFlipY]);
			texture.setName("distanceMap");
		}
		ctx.engine.setTarget(texture);
		passes = super.draw(ctx, passes);
		ctx.engine.setTarget(null);

		if( !hasTargetDepth )
			clear.apply(1);

		return passes;
	}

}