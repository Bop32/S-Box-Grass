
using Sandbox;
using System;
using System.Runtime.InteropServices;
using System.Transactions;


public struct GrassSettings
{
	public Model HighLodGrassModel { get; set; }
	public Model LowLodGrassModel { get; set; }
	public Terrain Terrain { get; set; }
	public int WorldChunksPerRow { get; set; }
	public int MaxGrassCount { get; set; }
	public Vector2 ChunkSize { get; set; }
	public float ClumpStrength { get; set; }
	public float ClumpSize { get; set; }

	public Texture ControlMap { get; set; }
}

public sealed class Grass : Component
{

	[Property]
	public readonly Model HighLodGrassModel = null;

	[Property]
	public readonly Model LowLodGrassModel = null;

	[Property]
	public readonly Terrain Terrain = null;

	[Header( "World Chunks" )]

	[Property]
	public int WorldChunksPerRow { get; set; }

	[Property]
	public int MaxGrassCount { get; set; } = 1000000;

	[Property]
	public float ClumpStrength { get; set; } = 5.0f;

	[Property]
	public float ClumpSize { get; set; } = 5.0f;

	[Property]
	public Texture ControlMap { get; private set; }

	GrassCustomObject grass;

	Dictionary<(float x, float y), float> heightMapChunks = new();

	private CameraComponent camera;

	PlayerController player;
	protected override void OnEnabled()
	{
		camera = GameObject.GetComponent<CameraComponent>();
		player = Scene.Get<PlayerController>();
		grass = new GrassCustomObject( Scene.SceneWorld, this, camera, player );
		//SimulateChunks();
	}

	public GrassSettings GetSettings()
	{
		return new GrassSettings
		{
			HighLodGrassModel = HighLodGrassModel,
			LowLodGrassModel = LowLodGrassModel,
			Terrain = Terrain,

			MaxGrassCount = MaxGrassCount,
			WorldChunksPerRow = WorldChunksPerRow,

			ClumpStrength = ClumpStrength,
			ClumpSize = ClumpSize,
			ControlMap = ControlMap
		};
	}

	private Vector2 WorldToTexelCPU( Vector2 worldXY, uint texWidth, uint texHeight )
	{
		Vector2 uv = (worldXY - new Vector2( Terrain.WorldPosition )) / Terrain.TerrainSize;

		if ( uv.x < 0.0f || uv.x > 1.0f || uv.y < 0.0f || uv.y > 1.0f ) return new Vector2( -9999 );

		int x = (int)(uv.x * (texWidth - 1));
		int y = (int)(uv.y * (texHeight - 1));

		return new Vector2( x, y );
	}

	private float SampleHeightCPU( Vector2 texel )
	{
		int w = Terrain.HeightMap.Width;
		int h = Terrain.HeightMap.Height;

		int x = (int)Math.Clamp( texel.x, 0, w );
		int y = (int)Math.Clamp( texel.y, 0, h );

		if ( heightMapChunks.TryGetValue( (x, y), out float cachedHeight ) )
		{
			return cachedHeight;
		}

		float height = Terrain.HeightMap.GetPixel( x, y ).r / 255.0f * Terrain.TerrainHeight;

		heightMapChunks.TryAdd( (x, y), height );

		return height;
	}


	protected override void OnUpdate()
	{
		//grass.RenderInteractionTexture();
	}
	protected override void DrawGizmos()
	{
		RenderChunks();
		//RenderChunksFromCamera();
	}

	const float INVALID_HEIGHT = -1.0f;

	private void RenderChunks()
	{
		float terrainSize = Terrain.TerrainSize;
		float terrainHeight = Terrain.TerrainHeight;

		float chunkSize = 1000;
		float halfChunkSize = chunkSize * 0.5f;
		Vector3 terrainWorldPosition = Terrain.WorldPosition;

		if ( camera == null ) camera = GameObject.GetComponent<CameraComponent>();

		if ( player == null ) player = Scene.Get<PlayerController>();

		Vector2 localPlayerPos = new Vector2( player.WorldPosition ) - new Vector2( terrainWorldPosition );

		Vector2 offsetCenter = localPlayerPos;// + camForward * gridExtent * 0.1f;								

		int totalChunks = WorldChunksPerRow * WorldChunksPerRow;
		int halfGrid = WorldChunksPerRow / 2;

		Vector3 terrainCenter = terrainWorldPosition + new Vector3( Terrain.TerrainSize, Terrain.TerrainHeight, 0 ) * 0.5f;
		for ( int i = 0; i < totalChunks; i++ )
		{
			int localX = (i % WorldChunksPerRow) - halfGrid;
			int localY = (i / WorldChunksPerRow) - halfGrid;

			float x = terrainCenter.x + localX * chunkSize + chunkSize * 0.5f;
			float y = terrainCenter.x + localY * chunkSize + chunkSize * 0.5f;
			float z = terrainWorldPosition.z;

			Vector3 chunkPosition = new Vector3( x, y, z );

			float height = GetHeightValueIgnoreOutOfBounds( chunkPosition, halfChunkSize );

			//if ( height < 0 ) continue;

			Vector3 min = new Vector3( chunkPosition.x - halfChunkSize, chunkPosition.y - halfChunkSize, z + height - 50 );
			Vector3 max = new Vector3( chunkPosition.x + halfChunkSize, chunkPosition.y + halfChunkSize, z + height + 50 );

			Color visibleColor = AABBInsideFrustum( min, max, GetCameraFrustum() ) ? Color.Green : Color.Red;

			DebugOverlay.Box( new BBox( min, max ), visibleColor );
			DebugOverlay.Text( chunkPosition.WithZ( chunkPosition.z + height + 50 ), $"Chunk {i}", 256 );
			//RenderSubChunks( chunkPosition, chunkSize, i );
		}
	}

	private float GetHeightValueIgnoreOutOfBounds( Vector3 chunkPosition, float halfChunkSize )
	{
		Vector2 bottomLeft = new Vector2( chunkPosition.x - halfChunkSize, chunkPosition.y - halfChunkSize );
		Vector2 bottomRight = new Vector2( chunkPosition.x + halfChunkSize, chunkPosition.y - halfChunkSize );
		Vector2 topLeft = new Vector2( chunkPosition.x - halfChunkSize, chunkPosition.y + halfChunkSize );
		Vector2 topRight = new Vector2( chunkPosition.x + halfChunkSize, chunkPosition.y + halfChunkSize );

		uint textureWidth = (uint)Terrain.HeightMap.Width;
		uint textureHeight = (uint)Terrain.HeightMap.Height;

		Vector2 bottomLeftTexel = WorldToTexelCPU( bottomLeft, textureWidth, textureHeight );
		Vector2 bottomRightTexel = WorldToTexelCPU( bottomRight, textureWidth, textureHeight );
		Vector2 topLeftTexel = WorldToTexelCPU( topLeft, textureWidth, textureHeight );
		Vector2 topRightTexel = WorldToTexelCPU( topRight, textureWidth, textureHeight );

		float height = MathF.Max( MathF.Max( SampleHeightCPU( bottomLeftTexel ), SampleHeightCPU( bottomRightTexel ) ),
			MathF.Max( SampleHeightCPU( topLeftTexel ), SampleHeightCPU( topRightTexel ) ) );

		return height;
	}

	private Color GetChunkColor( int offsetX, int offsetY )
	{
		int hash = offsetX * 73856093 ^ offsetY * 19349663;
		hash &= 0xFFFFFF;

		// Convert hash to RGB 0-1
		float r = ((hash >> 16) & 0xFF) / 255f;
		float g = ((hash >> 8) & 0xFF) / 255f;
		float b = (hash & 0xFF) / 255f;

		return new Color( r, g, b );
	}

	private float GetHeightValue( Vector3 position, Vector2 half )
	{
		Vector2 bottomLeft = new Vector2( position.x - half.x, position.y - half.y );
		Vector2 bottomRight = new Vector2( position.x + half.x, position.y - half.y );
		Vector2 topLeft = new Vector2( position.x - half.x, position.y + half.y );
		Vector2 topRight = new Vector2( position.x + half.x, position.y + half.y );

		uint textureWidth = (uint)Terrain.HeightMap.Width;
		uint textureHeight = (uint)Terrain.HeightMap.Height;


		Vector2 bottomLeftTexel = WorldToTexelCPU( bottomLeft, textureWidth, textureHeight );

		if ( bottomLeftTexel.x == -9999 && bottomLeftTexel.y == -9999 ) return INVALID_HEIGHT;

		Vector2 bottomRightTexel = WorldToTexelCPU( bottomRight, textureWidth, textureHeight );

		if ( bottomRightTexel.x == -9999 && bottomRightTexel.y == -9999 ) return INVALID_HEIGHT;

		Vector2 topLeftTexel = WorldToTexelCPU( topLeft, textureWidth, textureHeight );

		if ( topLeftTexel.x == -9999 && topLeftTexel.y == -9999 ) return INVALID_HEIGHT;

		Vector2 topRightTexel = WorldToTexelCPU( topRight, textureWidth, textureHeight );

		if ( topRightTexel.x == -9999 && topRightTexel.y == -9999 ) return INVALID_HEIGHT;

		float height = MathF.Max( MathF.Max( SampleHeightCPU( bottomLeftTexel ), SampleHeightCPU( bottomRightTexel ) ),
			MathF.Max( SampleHeightCPU( topLeftTexel ), SampleHeightCPU( topRightTexel ) ) );

		return height;
	}

	public bool AABBInsideFrustum( Vector3 min, Vector3 max, FrustumPlane[] frustumPlanes )
	{
		for ( int i = 0; i < 6; i++ )
		{
			Vector3 normal = frustumPlanes[i].Normal;

			Vector3 positive = new Vector3( normal.x >= 0 ? max.x : min.x, normal.y >= 0 ? max.y : min.y, normal.z >= 0 ? max.z : min.z );

			if ( Vector3.Dot( normal, positive ) - frustumPlanes[i].Distance < 0 ) return false;
		}

		return true;
	}

	private FrustumPlane[] GetCameraFrustum()
	{
		Frustum frustum = camera.GetFrustum();

		FrustumPlane[] planes = new FrustumPlane[6];

		const float shrinkAmount = 50.0f;

		planes[0] = new FrustumPlane { Normal = frustum.RightPlane.Normal, Distance = frustum.RightPlane.Distance - shrinkAmount };
		planes[1] = new FrustumPlane { Normal = frustum.LeftPlane.Normal, Distance = frustum.LeftPlane.Distance - shrinkAmount };
		planes[2] = new FrustumPlane { Normal = frustum.TopPlane.Normal, Distance = frustum.TopPlane.Distance - shrinkAmount };
		planes[3] = new FrustumPlane { Normal = frustum.BottomPlane.Normal, Distance = frustum.BottomPlane.Distance - shrinkAmount };
		planes[4] = new FrustumPlane { Normal = frustum.NearPlane.Normal, Distance = frustum.NearPlane.Distance - shrinkAmount };
		planes[5] = new FrustumPlane { Normal = frustum.FarPlane.Normal, Distance = frustum.FarPlane.Distance - shrinkAmount };

		return planes;
	}

	protected override void OnDestroy()
	{
		grass?.DestroyBuffers();
	}

	protected override void OnDisabled()
	{
		grass?.DestroyBuffers();
	}
}
