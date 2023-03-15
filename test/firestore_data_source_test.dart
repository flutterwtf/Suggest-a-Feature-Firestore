import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:suggest_a_feature/suggest_a_feature.dart';
import 'package:suggest_a_feature_firestore/src/data/firestore_data_source.dart';
import 'package:test/test.dart';

import 'utils/mocked_entities.dart';

void main() {
  final fakeFirestoreInstance = FakeFirebaseFirestore();
  late final Suggestion suggestionWithId;
  late final Comment commentWithId;

  final firestoreDataSource = FirestoreDataSource(
    userId: '1',
    firestoreInstance: fakeFirestoreInstance,
  );

  group('firestore data source', () {
    test('get suggestion by id', () async {
      final result = await firestoreDataSource.createSuggestion(
        mockedCreateSuggestionModel,
      );
      suggestionWithId = mockedSuggestion.copyWith(id: result.id);

      expect(
        await firestoreDataSource.getSuggestionById(suggestionWithId.id),
        suggestionWithId,
      );
    });

    test('get all suggestions', () async {
      expect(
        await firestoreDataSource.getAllSuggestions(),
        [suggestionWithId],
      );
    });

    test('update suggestion', () async {
      final updatedSuggestion = suggestionWithId.copyWith(
        title: 'Edited title',
      );

      expect(
        await firestoreDataSource.updateSuggestion(updatedSuggestion),
        updatedSuggestion,
      );
    });

    test('upvote', () async {
      expect(
        firestoreDataSource.upvote(suggestionWithId.id),
        isA<Future<void>>(),
      );
    });

    test('downvote', () async {
      expect(
        firestoreDataSource.downvote(suggestionWithId.id),
        isA<Future<void>>(),
      );
    });

    test('get all comments', () async {
      final mockedCreateCommentModel = CreateCommentModel(
        authorId: mockedComment.author.id,
        isAnonymous: mockedComment.isAnonymous,
        text: mockedComment.text,
        suggestionId: suggestionWithId.id,
        isFromAdmin: false,
      );
      final result = await firestoreDataSource.createComment(
        mockedCreateCommentModel,
      );
      commentWithId = mockedComment.copyWith(
        id: result.id,
        suggestionId: suggestionWithId.id,
      );

      expect(
        await firestoreDataSource.getAllComments(suggestionWithId.id),
        [commentWithId],
      );
    });

    test('delete comment', () async {
      expect(
        firestoreDataSource.deleteCommentById(commentWithId.id),
        isA<Future<void>>(),
      );
    });
  });
}
