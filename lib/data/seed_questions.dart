import '../models/quiz_question.dart';

const List<QuizQuestion> seedQuestions = [
  QuizQuestion(
    id: 'q1',
    section: 'Programming & Analysis',
    question: 'Egress width for an assembly space with occupant load 300?',
    options: ['44 in', '60 in', '72 in', '96 in'],
    correctOption: '60 in',
    explanation:
        'Use 0.2 in/person for stairs: 300 x 0.2 = 60 in. Many candidates mix this with 0.15 in/person.',
    codeReference: 'IBC 2021 Section 1005.3.1',
    examWeight: 15,
  ),
  QuizQuestion(
    id: 'q2',
    section: 'Project Management',
    question: 'What defines the project duration in CPM?',
    options: [
      'Lowest cost tasks',
      'Tasks with float',
      'Critical path tasks with zero total float',
      'Owner milestone dates',
    ],
    correctOption: 'Critical path tasks with zero total float',
    explanation:
        'The critical path controls completion date because those activities have no schedule slack.',
    codeReference: 'AIA Practice Management Principles',
    examWeight: 8,
  ),
  QuizQuestion(
    id: 'q3',
    section: 'PPD',
    question: 'Maximum ADA ramp slope for an accessible route?',
    options: ['1:8', '1:10', '1:12', '1:16'],
    correctOption: '1:12',
    explanation:
        'ADA limits ramp running slope to 1:12 max (8.33%). Typical miss: using preferred slopes as mandatory.',
    codeReference: '2010 ADA Standards Section 405.2',
    examWeight: 12,
  ),
];
