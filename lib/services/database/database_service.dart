import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../models/stern_product.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'stern_database.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE stern_product (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        name TEXT,
        mac_address TEXT UNIQUE,
        pairing_code TEXT,
        last_connected TEXT,
        last_updated TEXT,
        battery_voltage TEXT,
        sw_version TEXT,
        serial_number TEXT,
        valve_state TEXT,
        dayle_usage TEXT,
        last_filter_clean TEXT,
        manifacturing_date INTEGER DEFAULT 0,
        nearby INTEGER DEFAULT 0
      )
    ''');
  }

  // --- SternProduct CRUD ---

  Future<int> insertProduct(SternProduct product) async {
    final db = await database;
    return db.insert(
      'stern_product',
      product.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SternProduct>> getAllProducts() async {
    final db = await database;
    final maps = await db.query('stern_product');
    return maps.map((m) => SternProduct.fromMap(m)).toList();
  }

  Future<SternProduct?> getProductByMac(String macAddress) async {
    final db = await database;
    final maps = await db.query(
      'stern_product',
      where: 'mac_address = ?',
      whereArgs: [macAddress],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return SternProduct.fromMap(maps.first);
  }

  Future<int> updateProduct(SternProduct product) async {
    final db = await database;
    return db.update(
      'stern_product',
      product.toMap(),
      where: 'mac_address = ?',
      whereArgs: [product.macAddress],
    );
  }

  Future<int> deleteByMacAddress(String macAddress) async {
    final db = await database;
    return db.delete(
      'stern_product',
      where: 'mac_address = ?',
      whereArgs: [macAddress],
    );
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
