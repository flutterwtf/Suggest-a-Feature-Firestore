import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:suggest_a_feature/suggest_a_feature.dart';
import 'package:suggest_a_feature_firestore/suggest_a_feature_firestore.dart';

void main() async {
  final dataSource = FirestoreDataSource(
    userId: 'user-id',
    firestoreInstance: FirebaseFirestore.instance,
  );

  final createSuggestionModel = CreateSuggestionModel(
    title: 'My suggestion',
    description: 'Here is what I think should be added to the app...',
    authorId: '',
    isAnonymous: true,
    labels: [],
  );
  final createdSuggestion =
      await dataSource.createSuggestion(createSuggestionModel);

  await dataSource.deleteSuggestionById(createdSuggestion.id);
}
