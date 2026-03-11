
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
	public int SubChunksPerRow { get; set; }
	public int MaxNumberOfUsableChunks { get; set; }
	public int GrassCountPerChunk { get; set; }
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
	public int SubChunksPerRow { get; set; }

	[Property]
	public int MaxNumberOfUsableChunks { get; set; } = 4;

	[Property]
	public int GrassCountPerChunk { get; set; }

	[Property]
	public float ClumpStrength { get; set; } = 5.0f;

	[Property]
	public float ClumpSize { get; set; } = 5.0f;

	[Property]
	public Texture ControlMap { get; private set; }

	GrassCustomObject grass;

	Dictionary<(float x, float y), float> heightMapChunks = new();

	private CameraComponent camera;

	protected override void OnEnabled()
	{
		camera = GameObject.GetComponent<CameraComponent>();
		grass = new GrassCustomObject( Scene.SceneWorld, this, camera, Scene.Get<PlayerController>() );

		//SimulateChunks();
	}

	public GrassSettings GetSettings()
	{
		return new GrassSettings
		{
			HighLodGrassModel = HighLodGrassModel,
			LowLodGrassModel = LowLodGrassModel,
			Terrain = Terrain,

			GrassCountPerChunk = GrassCountPerChunk,
			SubChunksPerRow = SubChunksPerRow,
			WorldChunksPerRow = WorldChunksPerRow,
			MaxNumberOfUsableChunks = MaxNumberOfUsableChunks,

			ClumpStrength = ClumpStrength,
			ClumpSize = ClumpSize,
			ControlMap = ControlMap
		};
	}

	private Vector2 WorldToTexelCPU( Vector2 worldXY, uint texWidth, uint texHeight )
	{
		Vector2 uv = (worldXY - new Vector2( Terrain.WorldPosition )) / Terrain.TerrainSize;

		if ( uv.x < 0 || uv.x > 1 || uv.y < 0 || uv.y > 1 ) return new Vector2( -9999 );

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
		DebugOverlay.Texture( Terrain.ControlMap, new Rect( 0, 300, 512, 512 ) );
	}
	protected override void DrawGizmos()
	{
		RenderChunks();
		//RenderChunksFromCamera();
	}

	const float INVALID_HEIGHT = -1.0f;
	//private void RenderChunksFromCamera()
	//{
	//	int gridSize = WorldChunksPerRow;

	//	float chunkSize = 700;
	//	Vector3 playerPosition = Scene.Get<PlayerController>().WorldPosition;

	//	float baseX = MathF.Floor( playerPosition.x / chunkSize );
	//	float baseY = MathF.Floor( playerPosition.y / chunkSize );

	//	int half = gridSize / 2;

	//	int chunkCount = 1;

	//	for ( int ix = 0; ix < gridSize; ix++ )
	//	{
	//		for ( int iy = 0; iy < gridSize; iy++ )
	//		{
	//			int x = ix - half;
	//			int y = iy - half;

	//			float worldX = (baseX + x) * chunkSize + chunkSize * 0.5f;
	//			float worldY = (baseY + y) * chunkSize + chunkSize * 0.5f;
	//			float worldZ = Terrain.WorldPosition.z;

	//			Vector3 chunkCenter = new Vector3( worldX, worldY, worldZ );

	//			float height = GetHeightValue( chunkCenter, half );

	//			if ( height == INVALID_HEIGHT ) continue;

	//			Vector3 min = new Vector3( worldX - chunkSize * 0.5f, worldY - chunkSize * 0.5f, worldZ + height );
	//			Vector3 max = new Vector3( worldX + chunkSize * 0.5f, worldY + chunkSize * 0.5f, worldZ + height + 50 );

	//			Color visibleChunksColor = AABBInsideFrustum( min, max, GetCameraFrustum() ) ? Color.Green : Color.Red;

	//			BBox box = new( min, max );
	//			DebugOverlay.Box( box, visibleChunksColor );
	//			DebugOverlay.Text( box.Center.WithZ( box.Center.z + 25 ), $"{chunkCount}", 100 );

	//			chunkCount++;
	//		}
	//	}
	//}

	//private void RenderChunksFromCamera()
	//{
	//	Vector2 chunkSize = new Vector2( 700, 700 );
	//	CameraComponent camera = GetComponent<CameraComponent>();
	//	Vector3 cameraPosition = camera.WorldPosition;
	//	float worldZ = Terrain.WorldPosition.z;

	//	float fov = camera.FieldOfView;
	//	int rayCount = 30;
	//	int stepsPerRay = WorldChunksPerRow / 2;

	//	HashSet<(int, int)> visited = new();

	//	for ( int r = 0; r < rayCount; r++ )
	//	{
	//		float angle = MathX.Lerp( -fov * 0.5f, fov * 0.5f, r / (float)(rayCount - 1) );
	//		Rotation rayDir = camera.WorldRotation * Rotation.FromAxis( Vector3.Up, angle ).Normal;

	//		for ( int s = 1; s <= stepsPerRay; s++ )
	//		{
	//			Vector3 worldPos = cameraPosition + rayDir.Forward * s * chunkSize.x;

	//			int cx = (int)MathF.Floor( worldPos.x / chunkSize.x );
	//			int cy = (int)MathF.Floor( worldPos.y / chunkSize.y );

	//			if ( !visited.Add( (cx, cy) ) ) continue;

	//			float worldX = cx * chunkSize.x + chunkSize.x * 0.5f;
	//			float worldY = cy * chunkSize.y + chunkSize.y * 0.5f;
	//			Vector3 chunkCenter = new Vector3( worldX, worldY, worldZ );

	//			float height = GetHeightValue( chunkCenter, stepsPerRay );
	//			Vector3 min = new Vector3( worldX - chunkSize.x * 0.5f, worldY - chunkSize.y * 0.5f, worldZ + height );
	//			Vector3 max = new Vector3( worldX + chunkSize.x * 0.5f, worldY + chunkSize.y * 0.5f, worldZ + height + 50 );

	//			Color visibleChunksColor = AABBInsideFrustum( min, max, GetCameraFrustum() ) ? Color.Green : Color.Red;
	//			DebugOverlay.Box( new BBox( min, max ), visibleChunksColor );
	//		}
	//	}
	//}

	private void RenderChunks()
	{
		float terrainSize = Terrain.TerrainSize;
		float terrainHeight = Terrain.TerrainHeight;

		float chunkSize = 700.0f;//terrainSize / WorldChunksPerRow;
		float halfChunkSize = chunkSize * 0.5f;
		Vector3 terrainWorldPosition = Terrain.WorldPosition;

		if ( camera == null ) camera = GameObject.GetComponent<CameraComponent>();

		PlayerController player = Scene.Get<PlayerController>();

		Vector2 localPlayerPos = new Vector2( player.WorldPosition ) - new Vector2( Terrain.WorldPosition );
		Vector2 camForward = new Vector2( camera.WorldRotation.Forward ).Normal;
		float gridExtent = WorldChunksPerRow * chunkSize * 0.5f;

		Vector2 offsetCenter = localPlayerPos + camForward * gridExtent * 0.7f;

		Vector2Int playerChunk = new Vector2Int( (int)MathF.Floor( offsetCenter.x / chunkSize ), (int)MathF.Floor( offsetCenter.y / chunkSize ) );

		int totalChunks = WorldChunksPerRow * WorldChunksPerRow;
		int halfGrid = WorldChunksPerRow / 2;


		for ( int i = 0; i < totalChunks; i++ )
		{
			int localX = (i % WorldChunksPerRow) - halfGrid;
			int localY = (i / WorldChunksPerRow) - halfGrid;

			Vector2Int gridCoord = playerChunk + new Vector2Int( localX, localY );

			float x = Terrain.WorldPosition.x + gridCoord.x * chunkSize + chunkSize * 0.5f;
			float y = Terrain.WorldPosition.y + gridCoord.y * chunkSize + chunkSize * 0.5f;
			float z = terrainWorldPosition.z;

			Vector3 chunkPosition = new Vector3( x, y, z );

			float height = GetHeightValue( chunkPosition, halfChunkSize );

			if ( height < 0 ) continue;

			Vector3 min = new Vector3( chunkPosition.x - halfChunkSize, chunkPosition.y - halfChunkSize, z + height - 50 );
			Vector3 max = new Vector3( chunkPosition.x + halfChunkSize, chunkPosition.y + halfChunkSize, z + height + 50 );

			Color visibleColor = AABBInsideFrustum( min, max, GetCameraFrustum() ) ? Color.Green : Color.Red;

			//DebugOverlay.Box( new BBox( min, max ), visibleColor );
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

	private void RenderSubChunks( Vector3 chunkPosition, Vector2 chunkSize, int index )
	{
		Vector2 subChunkSize = new Vector2( chunkSize / SubChunksPerRow );

		Vector3 startSubChunkPosition = new Vector3( chunkPosition.x - chunkSize.x / 2, chunkPosition.y - chunkSize.y / 2, chunkPosition.z );

		uint textureWidth = (uint)Terrain.HeightMap.Width;
		uint textureHeight = (uint)Terrain.HeightMap.Height;

		for ( int i = 0; i < SubChunksPerRow * SubChunksPerRow; i++ )
		{
			int offsetX = i % SubChunksPerRow;
			int offsetY = i / SubChunksPerRow;

			float x = startSubChunkPosition.x + (offsetX + 0.5f) * subChunkSize.x;
			float y = startSubChunkPosition.y + (offsetY + 0.5f) * subChunkSize.y;
			float z = startSubChunkPosition.z;

			Vector3 subChunkPosition = new Vector3( x, y, z );

			if ( Vector3.DistanceBetween( subChunkPosition, Gizmo.Camera.Position ) > 6000.0f ) continue;

			Vector2 half = subChunkSize * 0.5f;

			float height = GetHeightValue( subChunkPosition, half );

			Vector3 min = new Vector3( subChunkPosition.x - subChunkSize.x * 0.5f + 1.0f, subChunkPosition.y - subChunkSize.y * 0.5f, z + height * 0.5f );
			Vector3 max = new Vector3( subChunkPosition.x + subChunkSize.x * 0.5f, subChunkPosition.y + subChunkSize.y * 0.5f, Terrain.WorldPosition.z + height );

			Vector3 cameraPos = Gizmo.Camera.Position;
			float distance = Vector3.DistanceBetween( min, cameraPos );
			float zOffset = distance * 0.005f;
			float xOffset = distance * 0.005f;
			min.z -= zOffset;
			min.x += xOffset;

			string visible = AABBInsideFrustum( min, max, GetCameraFrustum() ) ? "Visible" : "Not Visible";

			BBox box = new( min, max );

			DebugOverlay.Text( box.Center.WithZ( box.Center.z + min.z * 0.5f ), visible, 256 );
			DebugOverlay.Box( box, GetChunkColor( offsetX + index, offsetY + index ) );
		}
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
