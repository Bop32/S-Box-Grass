
using System.Transactions;

public sealed class Grass : Component
{

	[Property]
	private Model highLodGrassModel = null;

	[Property]
	private Model lowLodGrassModel = null;

	[Property]
	private Terrain terrain = null;

	[Property]
	public int grassCountPerChunk = 0;

	[Property]
	public int chunkCount = 0;

	[Property]
	public Vector2 chunkSize = Vector2.Zero;

	GrassCustomObject grass;

	protected override void OnAwake()
	{
		//Surely there is a better way because just wtf
		grass = new( Scene.SceneWorld, highLodGrassModel,
			lowLodGrassModel, terrain, grassCountPerChunk, chunkCount, chunkSize, GameObject.GetComponent<CameraComponent>() );

	}

	protected override void OnUpdate()
	{
		grass.RenderSceneObject();
	}

	protected override void OnDestroy()
	{
		grass.DestroyBuffers();
	}

	protected override void OnDisabled()
	{
		grass.DestroyBuffers();
	}
}
